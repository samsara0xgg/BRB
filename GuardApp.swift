import AppKit
import AVFoundation
import Carbon
import LocalAuthentication

struct GuardError: Error, CustomStringConvertible {
  let description: String
  init(_ d: String) { description = d }
}

/// Menu-bar dot: gray idle, yellow ring while counting down, yellow armed, red triggered.
///
/// Armed = camera recording, lid / motion / input watched, Mac kept awake with the lid shut.
/// A trigger locks the real screen, beeps softly for `softSeconds`, then sirens at full volume.
/// Unlocking the Mac (Touch ID or password on the lock screen) is the only way to disarm.
final class GuardApp: NSObject, NSApplicationDelegate {
  enum Phase: String { case idle, arming, armed, triggered }
  static let countdownSeconds = 5.0
  static let softSeconds = 10.0
  static let supportDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/GuardMode")
  static let stateFile = supportDir.appendingPathComponent("phase")

  private var phase = Phase.idle { didSet { persist(); render() } }
  private lazy var item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private var sensors: Sensors?
  private var motion = MotionDetector(), lid = LidDetector()
  private var recorder: Recorder?
  private var tap: InputTap?
  private var alarm: Alarm?
  private var watchdog: Timer?
  private var sigterm: DispatchSourceSignal?
  private var screenLocked = GuardApp.isScreenLocked()
  private var triggeredAt = Date.distantPast
  private var lastError: String?

  func applicationDidFinishLaunching(_ note: Notification) {
    let dnc = DistributedNotificationCenter.default()
    dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
      self?.screenLocked = true
      log("screen locked")
    }
    dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
      guard let self else { return }
      screenLocked = false
      log("screen unlocked")
      if phase == .armed || phase == .triggered { disarm("解锁") }
    }
    // `launchctl bootout` and logout end the app on purpose: put the Mac back, then stay down
    // (exit 0; launchd only relaunches after a crash or SIGKILL).
    signal(SIGTERM, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    source.setEventHandler { [weak self] in
      self?.disarm("SIGTERM")
      exit(0)
    }
    source.resume()
    sigterm = source
    resume()
  }

  func applicationWillTerminate(_ note: Notification) {
    if phase != .idle { disarm("退出") }
  }

  // MARK: arming

  @objc private func armClicked() {
    do {
      try preflight()
    } catch {
      lastError = "\(error)"
      render()
      log("arm refused: \(error)")
      NSApp.activate(ignoringOtherApps: true)
      let alert = NSAlert()
      alert.messageText = "警戒模式没有开启"
      alert.informativeText = "\(error)"
      alert.runModal()
      return
    }
    lastError = nil
    phase = .arming
    startWatching()
    log("arming, \(Int(GuardApp.countdownSeconds)) s countdown")
    DispatchQueue.main.asyncAfter(deadline: .now() + GuardApp.countdownSeconds) { [weak self] in
      guard let self, phase == .arming else { return }
      finishArming()
    }
  }

  /// Everything arming needs; throws a message naming each missing piece.
  private func preflight() throws {
    var missing: [String] = []
    if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) {
      missing.append("辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能，打开 GuardMode，然后再点一次")
    }
    if IsSecureEventInputEnabled() {
      missing.append("有程序开着安全输入（密码框，或终端的「安全键盘输入」），键盘按键会绕过警戒：先关掉")
    }
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: break
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { _ in }
      missing.append("摄像头权限：已弹出请求，允许后再点一次")
    default: missing.append("摄像头权限被拒：系统设置 → 隐私与安全性 → 摄像头，打开 GuardMode")
    }
    if Recorder.camera == nil { missing.append("找不到内置摄像头") }
    if Alarm.builtInSpeakers() == nil { missing.append("找不到 Mac 自带喇叭") }
    if GuardApp.lockScreen == nil { missing.append("系统锁屏功能不可用") }
    if missing.isEmpty && !setSleepDisabled(true) { missing.append("合盖不睡眠的管理员规则没装：见 README 第 1 步") }
    if !missing.isEmpty { throw GuardError(missing.joined(separator: "\n")) }
  }

  private func startWatching() {
    let r = Recorder()
    recorder = r
    do {
      log("recording to \(try r.start().path)")
    } catch {
      log("recording failed: \(error)")
    }
    let s = Sensors()
    s.onAccel = { [weak self] a in
      guard let self, let why = motion.feed(a) else { return }
      trigger(why)
    }
    s.onLid = { [weak self] angle in
      guard let self, let why = lid.feed(angle) else { return }
      trigger(why)
    }
    motion = MotionDetector()
    lid = LidDetector()
    s.start()
    sensors = s
    let t = InputTap()
    // Out of the tap callback: locking the screen and starting audio there would stall all input.
    t.onInput = { [weak self] what in DispatchQueue.main.async { self?.trigger(what) } }
    // Swallow while armed; after a trigger, only until the lock screen is up (or 2 s, if locking failed).
    t.shouldBlock = { [weak self] in
      guard let self, !screenLocked else { return false }
      return phase == .armed || (phase == .triggered && Date().timeIntervalSince(triggeredAt) < 2)
    }
    if !t.start() {
      log("event tap failed although Accessibility is granted; restarting so the grant takes effect")
      disarm("event tap failed")
      exit(1)  // launchd relaunches
    }
    tap = t
  }

  /// Captures the resting lid angle and orientation, or gives up when the sensors are silent.
  private func finishArming(then: (() -> Void)? = nil) {
    guard let s = sensors, s.accelReports > 0, s.lidReports > 0 else {
      lastError = "传感器没有数据（加速度 \(sensors?.accelReports ?? 0)，开合角度 \(sensors?.lidReports ?? 0)）"
      disarm("sensors silent")
      return
    }
    motion.baseline()
    lid.baseline()
    phase = .armed
    log("armed; lid at \(lid.rest.map { String(format: "%.0f°", $0) } ?? "-")")
    // The sensor processor can stop streaming (e.g. macOS resets the report interval): re-wake it.
    var seen = s.accelReports
    let dog = Timer(timeInterval: 5, repeats: true) { _ in
      if s.accelReports == seen { log("accelerometer silent for 5 s; waking the sensors again"); s.wake() }
      seen = s.accelReports
    }
    RunLoop.main.add(dog, forMode: .common)
    watchdog = dog
    then?()
  }

  private func stopWatching() {
    watchdog?.invalidate()
    watchdog = nil
    sensors?.stop()
    sensors = nil
    tap?.stop()
    tap = nil
    recorder?.stop()
    recorder = nil
    alarm?.stop()
    alarm = nil
    setSleepDisabled(false)
  }

  // MARK: trigger / disarm

  private func trigger(_ why: String) {
    guard phase == .armed else { return }
    triggeredAt = Date()
    phase = .triggered
    log("TRIGGERED: \(why)")
    let locked = GuardApp.lockScreen?() ?? -1
    log("lock screen returned \(locked)")
    soundAlarm(.soft)
    let at = triggeredAt  // a later session's trigger must not be escalated by this one's timers
    DispatchQueue.main.asyncAfter(deadline: .now() + GuardApp.softSeconds) { [weak self] in
      guard let self, phase == .triggered, triggeredAt == at else { return }
      soundAlarm(.loud)
    }
    // If the lock screen never came up, fall back to Touch ID / password right here.
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      guard let self, phase == .triggered, triggeredAt == at, !screenLocked else { return }
      log("screen did not lock; asking for Touch ID instead")
      authenticate(at)
    }
  }

  private func soundAlarm(_ level: Alarm.Level) {
    if alarm == nil { alarm = Alarm() }
    guard let alarm else { log("alarm impossible: no built-in speakers"); return }
    do {
      try alarm.play(level)
      log("alarm \(level)" + (level == .loud && Alarm.loudVolume < 1 ? " (test cap \(Alarm.loudVolume))" : ""))
    } catch {
      log("alarm failed: \(error)")
    }
  }

  private func authenticate(_ at: Date) {
    guard phase == .triggered, triggeredAt == at, !screenLocked else { return }
    NSApp.activate(ignoringOtherApps: true)
    LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解除警戒模式") { ok, error in
      DispatchQueue.main.async {  // GuardApp lives as long as the process
        guard self.phase == .triggered, self.triggeredAt == at else { return }
        if ok { self.disarm("Touch ID"); return }
        log("auth failed: \(error?.localizedDescription ?? "-")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.authenticate(at) }
      }
    }
  }

  /// Idle is written first, so a crash halfway through teardown cannot resume the alarm.
  private func disarm(_ how: String) {
    phase = .idle
    stopWatching()
    log("disarmed by \(how)")
  }

  // MARK: crash / kill resilience

  /// Picks up an armed or triggered session after a crash or SIGKILL in the same boot; anything
  /// older (a reboot) starts idle, and so does a triggered session whose lock screen was already
  /// unlocked by the owner while the app was down.
  private func resume() {
    let saved = (try? String(contentsOf: GuardApp.stateFile, encoding: .utf8)).flatMap(Phase.init(rawValue:)) ?? .idle
    let written = (try? FileManager.default.attributesOfItem(atPath: GuardApp.stateFile.path)[.modificationDate] as? Date) ?? .distantPast
    let resumable = (saved == .armed || (saved == .triggered && screenLocked)) && written > GuardApp.bootTime
    guard resumable, setSleepDisabled(true) else {
      phase = .idle
      Alarm.restoreLeftover()
      if GuardApp.sleepDisabled() { setSleepDisabled(false) }
      if saved != .idle { log("not resuming the \(saved) session") }
      return
    }
    log("resuming \(saved) session after a restart")
    phase = .arming
    startWatching()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      self?.finishArming(then: saved == .triggered ? { self?.trigger("警戒程序被结束后重启") } : nil)
    }
  }

  private func persist() {
    try? FileManager.default.createDirectory(at: GuardApp.supportDir, withIntermediateDirectories: true)
    try? phase.rawValue.write(to: GuardApp.stateFile, atomically: true, encoding: .utf8)
  }

  static var bootTime: Date {
    var tv = timeval()
    var size = MemoryLayout<timeval>.size
    sysctlbyname("kern.boottime", &tv, &size, nil, 0)
    return Date(timeIntervalSince1970: Double(tv.tv_sec))
  }

  static func isScreenLocked() -> Bool {
    (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
  }

  // MARK: system hooks

  /// Private login.framework call behind the "Lock Screen" menu item.
  static let lockScreen: (@convention(c) () -> Int32)? = {
    guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
          let f = dlsym(h, "SACLockScreenImmediate") else { return nil }
    return unsafeBitCast(f, to: (@convention(c) () -> Int32).self)
  }()

  /// `pmset disablesleep` keeps the Mac awake with the lid shut; needs the sudoers rule in README.
  @discardableResult
  private func setSleepDisabled(_ on: Bool) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    p.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    log("disablesleep \(on ? 1 : 0): exit \(p.terminationStatus)")
    return p.terminationStatus == 0
  }

  static func sleepDisabled() -> Bool {
    let p = Process(), pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["-g"]
    p.standardOutput = pipe
    guard (try? p.run()) != nil else { return false }
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return out.split(separator: "\n").contains { $0.contains("SleepDisabled") && $0.hasSuffix("1") }
  }

  // MARK: menu

  private func render() {
    let (color, filled): (NSColor, Bool) = switch phase {
    case .idle: (.systemGray, true)
    case .arming: (.systemYellow, false)
    case .armed: (.systemYellow, true)
    case .triggered: (.systemRed, true)
    }
    item.button?.image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      let dot = NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 8, height: 8))
      color.set()
      if filled { dot.fill() } else { dot.lineWidth = 1.5; dot.stroke() }
      return true
    }
    let menu = NSMenu()
    let label = ["idle": "警戒模式：关", "arming": "警戒模式：倒计时…", "armed": "警戒模式：开", "triggered": "警戒模式：报警中"][phase.rawValue]!
    menu.addItem(withTitle: label, action: nil, keyEquivalent: "")
    if phase == .idle {
      menu.addItem(withTitle: "开启警戒", action: #selector(armClicked), keyEquivalent: "").target = self
    } else {
      menu.addItem(withTitle: "解锁电脑即可解除", action: nil, keyEquivalent: "")
    }
    if Alarm.loudVolume < 1 { menu.addItem(withTitle: "测试中：最大音量限制为 \(Int(Alarm.loudVolume * 100))%", action: nil, keyEquivalent: "") }
    if let lastError { menu.addItem(withTitle: "上次失败：" + lastError.replacingOccurrences(of: "\n", with: "；"), action: nil, keyEquivalent: "") }
    menu.addItem(.separator())
    menu.addItem(withTitle: "打开录像文件夹", action: #selector(openFolder), keyEquivalent: "").target = self
    if phase == .idle { menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q") }
    item.menu = menu
  }

  @objc private func openFolder() {
    try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
    NSWorkspace.shared.open(Recorder.folder)
  }
}
