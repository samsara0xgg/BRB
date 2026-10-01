import AppKit
import IOKit.ps
import LocalAuthentication
import ServiceManagement

struct GuardError: Error, CustomStringConvertible {
  let description: String
  init(_ d: String) { description = d }
}

extension Trigger {
  /// Where the red starts on the notice's screen, in unit coordinates from the top-left: the
  /// keyboard below the screen, the lid's hinge at its top, Touch ID bottom-right, MagSafe left.
  /// A trackpad touch starts at the pointer instead.
  var floodOrigin: CGPoint {
    switch self {
    case .keyboard, .trackpad: CGPoint(x: 0.5, y: 1.02)
    case .lidClosed, .lidMoved: CGPoint(x: 0.5, y: 0)
    case .lifted, .tilted, .restarted: CGPoint(x: 0.5, y: 0.5)
    case .charger: CGPoint(x: 0, y: 0.85)
    case .finger, .powerKey: CGPoint(x: 1, y: 1.02)
    }
  }
}

/// The menu-bar shield and everything behind it.
///
/// Armed = the frosted screen up, the camera buffering the last 10 s in memory, lid / motion / input
/// watched, the Mac kept awake with the lid shut. A trigger floods the screen red, locks it, and
/// saves the recording; the siren starts at once for anything that looks like the Mac being taken
/// (lifted, the lid, the charger, the power button), after 10 soft seconds for a key, a touch or a
/// wrong finger. Disarm: a finger resting on Touch ID, from the countdown on, or unlocking the Mac.
/// While the screen is locked (display slept), keys and touches do not trigger: nobody can use a
/// locked Mac, and the owner has to wake it to unlock.
final class GuardApp: NSObject, NSApplicationDelegate {
  enum Phase: String { case idle, arming, armed, triggered }
  static let countdownSeconds = 5.0
  static let softSeconds = 10.0
  static let supportDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BRB")
  static let stateFile = supportDir.appendingPathComponent("phase")
  /// pmset calls in order, off the main thread (audit L5).
  static let pmsetQueue = DispatchQueue(label: "brb.pmset")

  /// A copy dragged into Applications adds itself to the login items once; a copy built from
  /// source has install.sh's LaunchAgent for that, which also restarts it.
  private func openAtLogin() {
    let agent = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.allen.guard-mode.plist")
    guard Bundle.main.bundlePath.hasPrefix("/Applications/"), !FileManager.default.fileExists(atPath: agent.path),
          !UserDefaults.standard.bool(forKey: "loginItemAdded") else { return }
    do {
      try SMAppService.mainApp.register()
      UserDefaults.standard.set(true, forKey: "loginItemAdded")
      log("added to the login items")
    } catch {
      log("not added to the login items: \(error)")
    }
  }

  /// The app was called Guard Mode until October 2026: its state and recordings move over once.
  static func moveOldFolders() {
    let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
    for (old, new) in [("Library/Application Support/GuardMode", supportDir), ("Movies/GuardMode", Recorder.folder)] {
      let from = home.appendingPathComponent(old)
      if fm.fileExists(atPath: from.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: from, to: new) }
    }
  }

  private var phase = Phase.idle { didSet { persist(); render() } }
  private lazy var item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let panel = Panel()
  private let veil = Veil()
  private var sensors: Sensors?
  private var motion = MotionDetector(), lid = LidDetector()
  private var recorder: Recorder?
  private var tap: InputTap?
  private let fingerprint = Fingerprint()
  private let live = Live()
  private var alarm: Alarm?
  private var watchdog: Timer?
  private var ticker: Timer?
  private var sigterm: DispatchSourceSignal?
  private var screenLocked = GuardApp.isScreenLocked()
  private var powerSource: CFRunLoopSource?
  private var pendingPower: DispatchWorkItem?
  // This session.
  private var test = false
  private var armedAt = Date()
  private var progress = 0.0
  private var armedOnAC = false
  private var degraded = false
  private var trigger: Trigger?
  private var triggeredAt = Date.distantPast
  private var softFrom: Date?
  private var sirenFrom: Date?
  private var clip: URL?
  private var photos = 0
  private var latestPhoto: Data?

  func applicationDidFinishLaunching(_ note: Notification) {
    GuardApp.moveOldFolders()
    Alarm.migrate()
    let dnc = DistributedNotificationCenter.default()
    dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
      guard let self else { return }
      screenLocked = true
      veil.model.locked = true
      log("screen locked")
    }
    dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
      guard let self else { return }
      screenLocked = false
      veil.model.locked = false
      log("screen unlocked")
      // During the countdown too: pressing Touch ID locks the screen, and unlocking means the owner is here.
      if phase != .idle { disarm(.unlock) }
    }
    // `launchctl bootout` and logout end the app on purpose: put the Mac back, then stay down
    // (exit 0; launchd only relaunches after a crash or SIGKILL).
    signal(SIGTERM, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    source.setEventHandler { [weak self] in
      self?.disarm(.stopped, exiting: true)
      exit(0)
    }
    source.resume()
    sigterm = source
    item.button?.target = self
    item.button?.action = #selector(statusClicked)
    item.button?.setAccessibilityLabel("BRB")
    panel.model.onArm = { [weak self] in self?.arm() }
    veil.onRebuild = { [weak self] in self?.listenForFinger() }
    watchPower()
    Recorder.prune()
    render()
    resume()
    openAtLogin()
    if !Prefs.introSeen && phase == .idle {  // first launch: a menu-bar app is easy to miss
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
        guard let self, phase == .idle, !panel.isShown, let button = item.button else { return }
        panel.toggle(from: button)
      }
    }
  }

  /// Quitting while armed would leave the Mac unguarded without anyone noticing (audit M1).
  /// Opening BRB again from Applications or Launchpad shows the panel: a menu-bar app has no
  /// window, and otherwise nothing would happen.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !panel.isShown, let button = item.button { panel.toggle(from: button) }
    return false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard phase == .idle else {
      log("quit refused while \(phase.rawValue)")
      return .terminateCancel
    }
    return .terminateNow
  }

  func applicationWillTerminate(_ note: Notification) {
    if phase != .idle { disarm(.stopped, exiting: true) }
  }

  @objc private func statusClicked() {
    guard let button = item.button else { return }
    panel.toggle(from: button)
  }

  // MARK: arming

  private func arm() {
    guard phase == .idle else { return }
    test = Prefs.testMode
    Alarm.silent = test
    armedAt = Date()
    progress = 0
    degraded = false
    trigger = nil
    softFrom = nil
    sirenFrom = nil
    clip = nil
    photos = 0
    latestPhoto = nil
    Recorder.prune()
    phase = .arming
    setSleepDisabled(true)
    startWatching()
    let seconds = GuardApp.countdownSeconds
    if Prefs.veil {
      veil.countdown(Int(seconds))
    }
    listenForFinger()
    log("arming, \(Int(seconds)) s countdown\(test ? ", test mode" : ""), \(Prefs.place.rawValue)")
    let start = Date()
    let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
      guard let self, phase == .arming else { timer.invalidate(); return }
      let elapsed = Date().timeIntervalSince(start)
      let remaining = max(1, Int((seconds - elapsed).rounded(.up)))
      if veil.model.remaining != remaining { veil.model.remaining = remaining }
      progress = min(1, elapsed / seconds)
      render()
      if elapsed >= seconds {
        timer.invalidate()
        finishArming()
      }
    }
    RunLoop.main.add(t, forMode: .common)
    ticker = t
  }

  private func startWatching() {
    let r = Recorder()
    do {
      try r.start()
      recorder = r
    } catch {
      log("camera failed, guarding without it: \(error)")  // the notice says "Not recording this time"
    }
    let m = veil.model
    m.test = test
    m.note = Prefs.note
    m.armedAt = armedAt
    m.recording = recorder != nil
    m.pushOn = Push.enabled
    m.locked = screenLocked
    live.start(recorder, state: LiveState(phase: phase.rawValue, since: LiveState.ms(armedAt), place: Prefs.place.rawValue, note: Prefs.note,
                                          push: Push.enabled, test: test, camera: recorder != nil))
    let s = Sensors()
    s.onAccel = { [weak self] a in
      guard let self, let hit = motion.feed(a) else { return }
      fire(hit.kind, hit.detail)
    }
    s.onLid = { [weak self] angle in
      guard let self, let hit = lid.feed(angle) else { return }
      fire(hit.kind, hit.detail)
    }
    motion = Prefs.place.motionDetector()
    lid = LidDetector()
    s.start()
    sensors = s
    let t = InputTap()
    // Out of the tap callback: locking the screen and starting audio there would stall all input.
    t.onInput = { [weak self] input in
      DispatchQueue.main.async { self?.handle(input) }
    }
    // Swallow while armed; after a trigger, until the lock screen is up (or the fallback dialog is).
    t.shouldBlock = { [weak self] in
      guard let self, !screenLocked else { return false }
      return phase == .armed || (phase == .triggered && Date().timeIntervalSince(triggeredAt) < 3.2)
    }
    if !t.start() {
      log("event tap failed although Accessibility is granted; restarting so the grant takes effect")
      disarm(.tapFailed)
      exit(1)  // launchd relaunches
    }
    tap = t
  }

  /// From the countdown on, so the owner's finger cancels it. A wrong finger only triggers once armed.
  private func listenForFinger() {
    guard phase == .arming || phase == .armed else { return }
    fingerprint.stop(returnFocus: false)
    fingerprint.start(in: veil.isUp ? veil.host : nil,
                      onAccept: { [weak self] in self?.disarm(.fingerprint) },
                      onReject: { [weak self] in self?.fire(.finger, "fingerprint not recognized") })
  }

  private func handle(_ input: InputTap.Input) {
    guard !screenLocked else { return }
    if phase == .arming {
      if input.keyCode == 53 { disarm(.escape) }  // esc, as the countdown says
      return
    }
    guard phase == .armed else { return }
    if input.kind == .powerKey {
      // Touch ID sits on the power key: give a resting finger 400 ms to disarm before the press counts.
      guard pendingPower == nil else { return }
      let work = DispatchWorkItem { [weak self] in
        self?.pendingPower = nil
        self?.fire(.powerKey, input.what)
      }
      pendingPower = work
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
      return
    }
    fire(input.kind, input.what, pointer: input.kind == .trackpad ? input.location : nil)
  }

  /// Captures the resting lid angle and orientation, or gives up when the sensors are silent.
  private func finishArming(resumed: Bool = false) {
    guard let s = sensors, s.accelReports > 0, s.lidReports > 0 else {
      log("sensors silent: accelerometer \(sensors?.accelReports ?? 0), lid \(sensors?.lidReports ?? 0) reports")
      disarm(.sensorsSilent)
      return
    }
    motion.baseline()
    lid.baseline()
    armedOnAC = GuardApp.onAC()
    phase = .armed
    veil.armed()
    live.update { $0.phase = "armed" }
    live.event("armed", Prefs.place.rawValue)
    log("armed; lid at \(lid.rest.map { String(format: "%.0f°", $0) } ?? "-"), \(armedOnAC ? "on the charger" : "on battery")")
    // The sensor processor can stop streaming (e.g. macOS resets the report interval): re-wake it,
    // and say so when it stays silent (audit H4: the shield goes half, the phone is told).
    var seen = s.accelReports
    var silentSince: Date?
    let dog = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
      guard let self else { return }
      if s.accelReports == seen {
        log("accelerometer silent for 5 s; waking the sensors again")
        s.wake()
        let since = silentSince ?? Date().addingTimeInterval(-5)
        silentSince = since
        if !degraded && Date().timeIntervalSince(since) >= 15 {
          degraded = true
          render()
          live.event("warning", "motion")
          if Push.enabled { Push.warning(L("The motion sensor stopped. The lid, the charger and touch still count."), test: test) }
        }
      } else if silentSince != nil {
        silentSince = nil
        if degraded {
          degraded = false
          render()
          log("accelerometer back")
        }
      }
      seen = s.accelReports
    }
    RunLoop.main.add(dog, forMode: .common)
    watchdog = dog
    if resumed { fire(.restarted, "the app was ended while alarming and relaunched") }
  }

  private func stopWatching(exiting: Bool) {
    ticker?.invalidate()
    ticker = nil
    pendingPower?.cancel()
    pendingPower = nil
    fingerprint.stop()
    watchdog?.invalidate()
    watchdog = nil
    sensors?.stop()
    sensors = nil
    live.stop()
    tap?.stop()
    tap = nil
    recorder?.stop()
    recorder = nil
    alarm?.stop()
    alarm = nil
    Alarm.silent = false
    setSleepDisabled(false, wait: exiting)
  }

  // MARK: trigger / disarm

  private func fire(_ kind: Trigger, _ detail: String, pointer: CGPoint? = nil) {
    guard phase == .armed else { return }
    pendingPower?.cancel()
    pendingPower = nil
    let at = Date()  // a later session's trigger must not be escalated by this one's timers
    triggeredAt = at
    trigger = kind
    phase = .triggered
    log("TRIGGERED: \(kind.rawValue), \(detail)")
    fingerprint.stop(returnFocus: false)  // the lock screen takes over
    veil.model.pushOn = Push.enabled
    veil.alarm(pointer: pointer, origin: kind.floodOrigin)

    // The red spreads first, so whoever touched it sees why; the tap swallows input meanwhile.
    DispatchQueue.main.asyncAfter(deadline: .now() + (veil.isUp ? 1.2 : 0)) { [weak self] in
      guard let self, phase == .triggered, triggeredAt == at else { return }
      log("lock screen returned \(GuardApp.lockScreen?() ?? -1)")
      // If the lock screen never came up, fall back to Touch ID / password right here.
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
        guard let self, phase == .triggered, triggeredAt == at, !screenLocked else { return }
        log("screen did not lock; asking for Touch ID instead")
        veil.close()  // the system dialog has to be visible
        authenticate(at)
      }
    }

    if kind.sirenAtOnce {
      sirenFrom = at
      soundAlarm(.loud)
    } else {
      softFrom = at
      soundAlarm(.soft)
      DispatchQueue.main.asyncAfter(deadline: .now() + GuardApp.softSeconds) { [weak self] in
        guard let self, phase == .triggered, triggeredAt == at else { return }
        sirenFrom = Date()
        soundAlarm(.loud)
        live.update { $0.siren = true }
        live.event("siren")
        if Push.enabled { Push.siren(test: test, link: live.alarmLink, photo: latestPhoto) }
      }
    }

    live.alarm()
    live.update {
      $0.phase = "triggered"
      $0.trigger = kind.rawValue
      $0.at = LiveState.ms(at)
      $0.siren = kind.sirenAtOnce
      $0.bumps = motion.bumps
    }
    live.event("triggered", kind.rawValue, at: at)
    let link = live.alarmLink
    if let recorder {
      clip = recorder.save { [weak self] photo in
        guard let self else { return }
        if let photo, triggeredAt == at { took(photo) }
        if Push.enabled { Push.alarm(kind, at: at, test: test, link: link, photo: photo) }
      }
      for delay in [2.0, 5.0] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
          guard let self, phase == .triggered, triggeredAt == at else { return }
          self.recorder?.photo { [weak self] photo in
            guard let self, let photo, phase == .triggered, triggeredAt == at else { return }
            took(photo)
          }
        }
      }
    } else if Push.enabled {
      Push.alarm(kind, at: at, test: test, link: link, photo: nil)
    }
  }

  private func took(_ photo: Data) {
    photos += 1
    latestPhoto = photo
    live.upload(photo)
    live.event("photo")
  }

  private func soundAlarm(_ level: Alarm.Level) {
    if alarm == nil { alarm = Alarm() }
    guard let alarm else { log("alarm impossible: no built-in speakers"); return }
    do {
      try alarm.play(level)
      log("alarm \(level)" + (Alarm.silent ? " (test mode: muted)" : ", volume \(Alarm.loudVolume)"))
    } catch {
      log("alarm failed: \(error)")
    }
  }

  private func authenticate(_ at: Date) {
    guard phase == .triggered, triggeredAt == at, !screenLocked else { return }
    NSApp.activate(ignoringOtherApps: true)
    LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L("Stop guarding")) { ok, error in
      DispatchQueue.main.async {  // GuardApp lives as long as the process
        guard self.phase == .triggered, self.triggeredAt == at else { return }
        if ok { self.disarm(.password); return }
        log("auth failed: \(error?.localizedDescription ?? "-")")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.authenticate(at) }
      }
    }
  }

  /// Idle is written first, so a crash halfway through teardown cannot resume the alarm.
  private func disarm(_ how: Disarm, exiting: Bool = false) {
    guard phase != .idle else { return }
    let was = phase
    phase = .idle
    let now = Date()
    let session = Session(armed: armedAt, ended: now, trigger: trigger, triggeredAt: trigger == nil ? nil : triggeredAt, disarm: how,
                          bumps: motion.bumps, softSeconds: softFrom.map { Int((sirenFrom ?? now).timeIntervalSince($0)) } ?? 0,
                          sirenSeconds: sirenFrom.map { Int(now.timeIntervalSince($0)) } ?? 0, photos: photos,
                          clip: clip?.lastPathComponent, test: test)
    let guarded = was == .armed || was == .triggered
    if guarded || how == .sensorsSilent { History.add(session) }
    // Test mode covers one run, then turns itself off (audit H1).
    if test && guarded { Prefs.testMode = false }
    if trigger != nil && Push.enabled { Push.disarmed(how, at: now, test: test) }
    live.update {
      $0.phase = "idle"
      $0.siren = false
      $0.pass = nil  // the push link stops working here
    }
    live.event(guarded ? "disarmed" : "cancelled", how.rawValue, at: now)
    stopWatching(exiting: exiting)
    if !exiting {
      if guarded {
        veil.welcome(session.welcome, toward: item.button?.window?.frame)
      } else {
        veil.cancel()
      }
    }
    log("disarmed: \(how.rawValue)")
    // ponytail: macOS can restart the camera stream by itself after we stopped it (live 2026-09-24:
    // a Touch ID press powered the camera off and on around a disarm, and the light stayed on with
    // nobody reading it). Relaunching drops that stream; a real fix needs CoreMediaIO to honor the stop.
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
      guard self?.phase == .idle, Recorder.running == 0, Recorder.hardwareStreaming,
            Recorder.camera?.isInUseByAnotherApplication == false else { return }
      log("camera still streaming after the disarm with nobody using it; relaunching to release it")
      exit(1)  // launchd relaunches after a non-zero exit
    }
  }

  // MARK: crash / kill resilience

  /// Picks up an armed or triggered session after a crash or SIGKILL in the same boot; anything
  /// older (a reboot) starts idle, and so does a triggered session whose lock screen was already
  /// unlocked by the owner while the app was down.
  private func resume() {
    let saved = (try? String(contentsOf: GuardApp.stateFile, encoding: .utf8)).flatMap(Phase.init(rawValue:)) ?? .idle
    let written = (try? FileManager.default.attributesOfItem(atPath: GuardApp.stateFile.path)[.modificationDate] as? Date) ?? .distantPast
    let resumable = (saved == .armed || (saved == .triggered && screenLocked)) && written > GuardApp.bootTime
    guard resumable else {
      phase = .idle
      Alarm.restoreLeftover()
      GuardApp.pmsetQueue.async { if GuardApp.sleepDisabled() { GuardApp.pmset(false) } }
      if saved != .idle { log("not resuming the \(saved.rawValue) session") }
      return
    }
    log("resuming \(saved.rawValue) session after a restart")
    test = Prefs.testMode  // still on: a test run turns it off only at its disarm
    Alarm.silent = test
    armedAt = written
    phase = .arming
    setSleepDisabled(true)
    startWatching()
    if Prefs.veil { veil.guarding() }
    listenForFinger()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
      guard let self, phase == .arming else { return }
      finishArming(resumed: saved == .triggered)
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

  /// Unplugging the charger of an armed Mac is a trigger (a charger is easy to walk off with).
  /// Plugging one in while armed counts too, from then on (audit L7).
  private func watchPower() {
    let me = Unmanaged.passUnretained(self).toOpaque()
    guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
      let app = Unmanaged<GuardApp>.fromOpaque(ctx!).takeUnretainedValue()
      guard app.phase == .armed else { return }
      if GuardApp.onAC() {
        if !app.armedOnAC { log("charger plugged in while armed; unplugging it now triggers") }
        app.armedOnAC = true
      } else if app.armedOnAC {
        app.fire(.charger, "charger unplugged")
      }
    }, me)?.takeRetainedValue() else { log("power-source notifications unavailable"); return }
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    powerSource = src
  }

  static func onAC() -> Bool {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    return IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? == "AC Power"
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
  /// In order and off the main thread; `wait` when the process is about to exit.
  private func setSleepDisabled(_ on: Bool, wait: Bool = false) {
    if wait {
      _ = GuardApp.pmsetQueue.sync { GuardApp.pmset(on) }
    } else {
      GuardApp.pmsetQueue.async { GuardApp.pmset(on) }
    }
  }

  @discardableResult
  static func pmset(_ on: Bool) -> Bool {
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

  // MARK: menu bar

  private func render() {
    let look: StatusIcon.Look = switch phase {
    case .idle: .idle
    case .arming: .arming(progress)
    case .armed: test ? .test : (degraded || recorder == nil) ? .partial : .armed
    case .triggered: .alarm
    }
    let tip = switch phase {
    case .idle: L("Not guarding")
    case .arming: L("Starting…")
    case .armed: L("Guarding")
    case .triggered: L("Alarm raised")
    }
    item.button?.image = StatusIcon.image(look)
    item.button?.toolTip = tip
    if panel.model.phase != phase { panel.model.phase = phase }
  }
}
