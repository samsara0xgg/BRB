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
  /// What a triggered alarm is doing, in the phone's words; `hushed`: its owner silenced it from the phone.
  private enum Stage: String { case soft, siren, hushed }
  static let countdownSeconds = 5.0
  static let softSeconds = 10.0
  /// After a hush, movement that was already under way does not sound the siren again for this long.
  static let hushGrace = 5.0
  /// The battery and the checks go to a paired phone this often (and when they change).
  static let phoneRefresh = 300.0
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

  /// The app's id was com.allen.guard-mode until 1.1. Its settings, the relay key and the token the
  /// paired phones hold live under that id: copied over once, so nothing is set up or paired again.
  /// Not the login item (registered under the old id) or the ntfy alerts, which are gone.
  static func adoptOldSettings() {
    let d = UserDefaults.standard, oldID = "com.allen.guard-mode"
    guard let id = Bundle.main.bundleIdentifier, id != oldID, !d.bool(forKey: "adoptedOldSettings") else { return }
    let mine = d.persistentDomain(forName: id) ?? [:]
    let old = d.persistentDomain(forName: oldID) ?? [:]
    let skip: Set = ["loginItemAdded", "pushEnabled", "ntfyTopic"]
    let moved = old.filter { mine[$0.key] == nil && !skip.contains($0.key) }
    for (key, value) in moved { d.set(value, forKey: key) }
    d.set(true, forKey: "adoptedOldSettings")
    if !moved.isEmpty { log("settings brought over from \(oldID): \(moved.count)") }
  }

  /// 1.0 was BRB.app, under the old id. Back in 5 lands next to it in Applications instead of
  /// replacing it, and its login item would start a second guard at the next login: so a copy
  /// installed in Applications quits the old one and puts it in the Trash.
  static func retireOldApp() {
    let oldID = "com.allen.guard-mode", fm = FileManager.default
    guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
    for dir in ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path] {
      let old = URL(fileURLWithPath: dir).appendingPathComponent("BRB.app")
      guard Bundle(url: old)?.bundleIdentifier == oldID else { continue }
      for app in NSRunningApplication.runningApplications(withBundleIdentifier: oldID) where app.bundleURL?.standardizedFileURL == old.standardizedFileURL {
        kill(app.processIdentifier, SIGTERM)  // 1.0 puts the Mac back and quits on SIGTERM
      }
      do {
        try fm.trashItem(at: old, resultingItemURL: nil)
        log("moved the old BRB.app to the Trash")
      } catch {
        log("the old BRB.app stays in \(dir): \(error.localizedDescription)")
      }
    }
  }

  /// The app was called Guard Mode, then BRB until 1.1: its state and recordings move over once.
  static func moveOldFolders() {
    let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
    for (old, new) in [("Library/Application Support/GuardMode", supportDir), ("Movies/BRB", Recorder.folder), ("Movies/GuardMode", Recorder.folder)] {
      let from = home.appendingPathComponent(old)
      if fm.fileExists(atPath: from.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: from, to: new) }
    }
  }

  private var phase = Phase.idle { didSet { persist(); render() } }
  private lazy var item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let panel = Panel()
  private lazy var settings = SettingsWindow(model: panel.model)
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
  /// When the soft stage ended: the siren's start, or the owner calling it off.
  private var softTo: Date?
  /// When the siren that is sounding now started; nil while it is silent.
  private var sirenFrom: Date?
  /// Seconds of siren in stretches the owner has since silenced.
  private var sirenSpent = 0.0
  private var stage: Stage?
  private var hushedAt = Date.distantPast
  /// The Mac is being carried right now (while triggered), as the phone was last told.
  private var carried = false
  private var carriedAt = Date.distantPast
  private var clip: URL?
  private var photos = 0
  private var photoTimes: [Int64] = []
  // The menu-bar shield between sessions (audit C5, D4).
  /// The look it keeps while the notice flies back, so it changes as the notice lands.
  private var parked: StatusIcon.Look?
  private var parkToken = 0
  /// Green with a tick for 1.6 s after the landing.
  private var landing = false
  private var landingToken = 0
  private var iconScale: CGFloat = 1
  /// A cancel pours the amber back out: the arming level falling to zero.
  private var drainLevel = 0.0
  private var iconTimer: Timer?
  /// A real alarm the owner hasn't looked at yet: a red dot until the panel shows it.
  private var unseen = false
  // The iPhone app.
  /// The relay socket is wanted between sessions: a phone is paired, or a pairing code is good.
  private var holding = false
  private var mac: LiveState.Mac?
  private var baseHealth = LiveState.Health(ax: true, cam: true, lid: true, mot: true)
  private var phoneTimer: Timer?
  private var prefsPending = false

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
      Relaunch.standDown()
      exit(0)
    }
    source.resume()
    sigterm = source
    item.button?.target = self
    item.button?.action = #selector(statusClicked)
    item.button?.setAccessibilityLabel("Back in 5")
    panel.anchor = { [weak self] in self?.item.button }
    let m = panel.model
    m.onArm = { [weak self] silentOnce in self?.arm(silentOnce: silentOnce) }
    m.onCancel = { [weak self] in self?.disarm(.escape) }
    m.onSettings = { [weak self] tab in self?.showSettings(tab) }
    m.onIntro = { [weak self] in
      self?.settings.close()
      self?.panel.show(intro: true)
    }
    m.onSeen = { [weak self] in
      guard let self, unseen else { return }
      unseen = false
      render()
    }
    // A permission granted in System Settings: back to the panel, where its row ticks off.
    m.onReopen = { [weak self] in
      guard let self, phase == .idle, !settings.isVisible else { return }
      panel.show()
    }
    veil.onRebuild = { [weak self] in self?.listenForFinger() }
    veil.onLanded = { [weak self] in self?.landed() }
    live.onCommand = { [weak self] command in self?.phone(command) }
    live.onPaired = { [weak self] device in self?.paired(by: device) }
    m.pairing.onWatch = { [weak self] _ in self?.syncPhone() }
    m.onChecks = { [weak self] checks in self?.checked(checks) }
    // The iPhone sees the Mac's place, note, volume and test mode: a change in the panel, or anywhere
    // in the defaults, is looked at a moment later. A new link unpairs every phone.
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.prefsChanged()
    }
    NotificationCenter.default.addObserver(forName: Live.didReset, object: nil, queue: .main) { [weak self] _ in self?.linkReset() }
    unseen = History.load().contains { $0.alarmed && !$0.test && $0.ended > Prefs.alarmsSeenAt }
    installMenu()
    watchPower()
    Recorder.prune()
    render()
    resume()
    syncPhone()
    openAtLogin()
    GuardApp.retireOldApp()
    if !Prefs.introSeen && phase == .idle {  // first launch: a menu-bar app is easy to miss
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
        guard let self, phase == .idle, !panel.isShown else { return }
        panel.show()
      }
    }
  }

  /// Quitting while armed would leave the Mac unguarded without anyone noticing (audit M1).
  /// Opening BRB again from Applications or Launchpad shows the panel: a menu-bar app has no
  /// window, and otherwise nothing would happen.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !panel.isShown { panel.show() }
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
    Relaunch.standDown()
  }

  @objc private func statusClicked() {
    panel.toggle()
  }

  @objc private func openSettings() {
    showSettings(.general)
  }

  /// Settings is for when nothing runs: the panel steps aside for the window.
  private func showSettings(_ tab: SettingsTab) {
    guard phase == .idle else { return }
    panel.close()
    settings.show(tab)
  }

  /// A menu-bar app shows no menu bar of its own, but its windows still need the usual keys: ⌘, for
  /// Settings, ⌘W, ⌘Q, and copy and paste in the text fields.
  private func installMenu() {
    let app = NSMenu()
    app.addItem(withTitle: L("Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
    app.addItem(.separator())
    app.addItem(withTitle: L("Quit Back in 5"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let window = NSMenu(title: "Window")
    window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let main = NSMenu()
    for menu in [app, edit, window] {
      let holder = NSMenuItem()
      holder.submenu = menu
      main.addItem(holder)
    }
    NSApp.mainMenu = main
  }

  // MARK: arming

  /// `silentOnce`: ⌥ was held on the start button, so this run is a test without test mode.
  private func arm(silentOnce: Bool = false) {
    guard phase == .idle else { return }
    test = Prefs.testMode || silentOnce
    Alarm.silent = test
    armedAt = Date()
    progress = 0
    degraded = false
    trigger = nil
    softFrom = nil
    softTo = nil
    sirenFrom = nil
    sirenSpent = 0
    stage = nil
    carried = false
    clip = nil
    photos = 0
    photoTimes = []
    parked = nil
    landing = false
    stopIconAnimation()
    settings.close()
    Recorder.prune()
    trimLog()  // a menu-bar app runs for weeks between launches
    phase = .arming
    setSleepDisabled(true)
    startWatching()
    let seconds = GuardApp.countdownSeconds
    let start = Date()
    panel.model.countdownFrom = start
    panel.model.remaining = Int(seconds)
    if Prefs.veil {
      veil.countdown(Int(seconds))
    }
    listenForFinger()
    log("arming, \(Int(seconds)) s countdown\(test ? silentOnce ? ", silent once" : ", test mode" : ""), \(Prefs.place.rawValue)")
    // 30 times a second, so the amber rises smoothly in the menu bar.
    let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
      guard let self, phase == .arming else { timer.invalidate(); return }
      let elapsed = Date().timeIntervalSince(start)
      let remaining = max(1, Int((seconds - elapsed).rounded(.up)))
      if veil.model.remaining != remaining { veil.model.remaining = remaining }
      if panel.model.remaining != remaining { panel.model.remaining = remaining }
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
    m.pushOn = Prefs.phonePaired
    m.locked = screenLocked
    var first = LiveState(phase: phase.rawValue, since: LiveState.ms(armedAt), armEnd: LiveState.ms(armedAt.addingTimeInterval(GuardApp.countdownSeconds)),
                          place: Prefs.place.rawValue, note: Prefs.note, vol: volumePercent, test: test, camera: recorder != nil)
    first.lastEnd = lastEnd
    if holding {  // the Mac's own details go to the relay only for a phone that is paired
      first.mac = mac ?? MacInfo.card()
      first.health = health
    }
    live.start(recorder, state: first)
    let s = Sensors()
    s.onAccel = { [weak self] a in
      guard let self else { return }
      let hit = motion.feed(a)
      if phase == .triggered { follow(hit) }
      guard let hit else { return }
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
    panel.close()  // from here a click is a touch
    veil.armed()
    live.update(event: "armed", key: Prefs.place.rawValue) {
      $0.phase = "armed"
      $0.armEnd = 0
    }
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
          live.update(event: "warning", key: "motion") { if self.holding { $0.health = self.health } }
        }
      } else if silentSince != nil {
        silentSince = nil
        if degraded {
          degraded = false
          render()
          publishPhone()
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
    veil.model.pushOn = Prefs.phonePaired
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

    carried = false
    if kind.sirenAtOnce {
      sirenFrom = at
      stage = .siren
      soundAlarm(.loud)
    } else {
      softFrom = at
      stage = .soft
      soundAlarm(.soft)
      DispatchQueue.main.asyncAfter(deadline: .now() + GuardApp.softSeconds) { [weak self] in
        // Not when the owner called it off from the phone meanwhile.
        guard let self, phase == .triggered, triggeredAt == at, stage == .soft else { return }
        let now = Date()
        softTo = now
        sirenFrom = now
        stage = .siren
        soundAlarm(.loud)
        live.update(event: "siren", at: now) {
          $0.siren = true
          $0.stage = Stage.siren.rawValue
          $0.softEnd = nil
        }
      }
    }

    live.alarm()
    live.update(event: "triggered", key: kind.rawValue, at: at) {
      $0.phase = "triggered"
      $0.trigger = kind.rawValue
      $0.at = LiveState.ms(at)
      $0.siren = kind.sirenAtOnce
      $0.stage = (kind.sirenAtOnce ? Stage.siren : Stage.soft).rawValue
      $0.softEnd = kind.sirenAtOnce ? nil : LiveState.ms(at.addingTimeInterval(GuardApp.softSeconds))
      $0.carried = false
      $0.bumps = motion.bumps
    }
    if let recorder {
      clip = recorder.save { [weak self] photo in
        guard let self else { return }
        if let photo, triggeredAt == at { took(photo) }
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
    }
  }

  private func took(_ photo: Data) {
    let at = Date()
    photos += 1
    photoTimes.append(LiveState.ms(at))
    live.upload(photo, at: at)
    live.event("photo", at: at)
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
    let guarded = was == .armed || was == .triggered
    // The shield keeps its look until the notice lands in it; a real alarm leaves a red dot.
    if guarded && !exiting && veil.isUp { park(shieldLook()) }
    if guarded && trigger != nil && !test { unseen = true }
    phase = .idle
    let now = Date()
    let session = Session(armed: armedAt, ended: now, trigger: trigger, triggeredAt: trigger == nil ? nil : triggeredAt, disarm: how,
                          bumps: motion.bumps, softSeconds: softFrom.map { Int((softTo ?? now).timeIntervalSince($0)) } ?? 0,
                          sirenSeconds: Int(sirenSpent + (sirenFrom.map { now.timeIntervalSince($0) } ?? 0)), photos: photos,
                          clip: clip?.lastPathComponent, test: test)
    let recorded = guarded || how == .sensorsSilent
    if recorded { History.add(session) }
    // Test mode covers one run, then turns itself off (audit H1).
    if test && guarded { Prefs.testMode = false }
    // One state with its event: the relay (and the push it may send) reads how it ended from them together.
    let last = lastEnd
    degraded = false
    live.update(event: guarded ? "disarmed" : "cancelled", key: how.rawValue, at: now) {
      $0.phase = "idle"
      $0.since = 0
      $0.armEnd = 0
      $0.lastEnd = last
      $0.test = Prefs.testMode  // idle: whether the next run is a test
      $0.siren = false
      $0.stage = nil
      $0.softEnd = nil
      $0.carried = false
      $0.pass = nil  // the push link stops working here
      if holding { $0.health = health }
    }
    if recorded { live.session(sessionRecord(session)) }
    stopWatching(exiting: exiting)
    stage = nil
    carried = false
    if !exiting {
      if guarded {
        veil.welcome(session.welcome, toward: item.button?.window?.frame)  // lands at once when the veil is down
      } else {
        veil.cancel()
        drain(from: progress)
        panel.model.refresh()  // a countdown cancelled from the panel: it goes back to the start button
      }
    }
    log("disarmed: \(how.rawValue)")
    refreshIdle()
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

  // MARK: iPhone app

  private var volumePercent: Int { Int((Alarm.loudVolume * 100).rounded()) }

  /// When the previous session ended, from the history.
  private var lastEnd: Int64? { History.load().first.map { LiveState.ms($0.ended) } }

  /// What works, as the phone is told: the last checks, and the motion sensor unless it went quiet.
  private var health: LiveState.Health {
    var h = baseHealth
    h.mot = !degraded
    return h
  }

  /// A finished session for the iPhone's history: the Recent list's facts, with its photos and events.
  private func sessionRecord(_ s: Session) -> SessionRecord {
    SessionRecord(id: String(LiveState.ms(s.armed)), start: LiveState.ms(s.armed), end: LiveState.ms(s.ended), place: live.state.place,
                  bumps: s.bumps, kind: s.test ? "test" : s.alarmed ? "alarm" : "quiet", trigger: s.trigger?.rawValue,
                  at: s.triggeredAt.map(LiveState.ms), how: s.disarm.rawValue, soft: s.softSeconds, siren: s.sirenSeconds,
                  photos: photoTimes, events: live.state.events, clip: s.clip)
  }

  /// Keeps the socket to the relay open between sessions while a phone is paired (or a pairing code
  /// is good, to hear it claimed), and the phone's picture of this Mac fresh. Cheap to call: it acts
  /// only when the answer changes.
  private func syncPhone() {
    let want = Prefs.phonePaired || panel.model.pairing.watching
    guard want != holding else { return }
    holding = want
    phoneTimer?.invalidate()
    phoneTimer = nil
    if want {
      mac = MacInfo.card()
      checkHealth()
      let t = Timer(timeInterval: GuardApp.phoneRefresh, repeats: true) { [weak self] _ in
        self?.mac = MacInfo.card()
        self?.checkHealth()
        self?.publishPhone()
      }
      RunLoop.main.add(t, forMode: .common)
      phoneTimer = t
    } else {
      mac = nil
    }
    live.keepOpen(want, idle: idleState())
    log(want ? "phone link kept open between sessions" : "phone link closed between sessions")
    publishPhone()  // a session that was resumed before this knew of the phone
  }

  /// The Mac as the phone sees it between sessions: the settings it can change, whether this Mac is
  /// fit to start, and how the last session went (its events stay until the next one starts).
  private func idleState() -> LiveState {
    var s = live.state
    s.v = 3
    s.phase = "idle"
    s.since = 0
    s.armEnd = 0
    s.lastEnd = lastEnd
    s.place = Prefs.place.rawValue
    s.note = Prefs.note
    s.vol = volumePercent
    s.test = Prefs.testMode  // the next run is a test
    s.camera = baseHealth.cam
    s.siren = false
    s.stage = nil
    s.softEnd = nil
    s.carried = false
    s.pass = nil
    s.mac = mac ?? MacInfo.card()
    s.health = health
    return s
  }

  /// Sends the idle picture again if anything in it changed.
  private func refreshIdle() {
    guard holding, phase == .idle else { return }
    let next = idleState()
    guard next != live.state else { return }
    live.update { $0 = next }
  }

  /// A paired phone is told what changed: the idle picture, or during a session the Mac's card and health.
  private func publishPhone() {
    guard holding else { return }
    guard phase != .idle else { return refreshIdle() }
    let card = mac, current = health
    guard live.state.mac != card || live.state.health != current else { return }
    live.update {
      $0.mac = card
      $0.health = current
    }
  }

  private func checkHealth() {
    Preflight.run { [weak self] checks in self?.checked(checks) }
  }

  /// New results of the checks (the panel runs them once a second while it is open).
  private func checked(_ checks: [Check]) {
    guard holding else { return }
    func fine(_ id: Check.ID) -> Bool { checks.first { $0.id == id }?.ok ?? true }
    let next = LiveState.Health(ax: fine(.accessibility), cam: fine(.camera), lid: fine(.sleep), mot: true)
    guard next != baseHealth else { return }
    baseHealth = next
    publishPhone()
  }

  /// The place, note, volume or test mode may have changed in the panel; or a phone got paired or unpaired.
  private func prefsChanged() {
    guard !prefsPending else { return }
    prefsPending = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self else { return }
      prefsPending = false
      syncPhone()
      refreshIdle()
    }
  }

  /// A new link (from the panel, Settings or the phone): every phone is unpaired and the relay has a
  /// new room. A session that is running moves to it; between sessions the socket is let go.
  private func linkReset() {
    panel.model.pairing.finish()
    syncPhone()
    live.reconnect()
  }

  /// A phone claimed the pairing code. From now on the socket stays open between sessions.
  private func paired(by device: String) {
    log("paired with \(device)")
    Prefs.phonePaired = true
    Prefs.phoneName = String(device.prefix(40))
    panel.model.pairing.finish()
    syncPhone()
    live.event("paired")
  }

  /// A command from a paired phone, through the relay. Every one is answered, so the app is never
  /// left waiting; a `hush`, `stop` or `disarm` that arrives late finds nothing to do and says ok.
  private func phone(_ c: PhoneCommand) {
    log("phone command: \(c.kind.rawValue) (\(c.id))")
    if let by = c.by { log("  confirmed by \(by)") }  // the phone asked for Face ID; the Mac cannot check it
    switch c.kind {
    case .start:
      phoneStart(c)
    case .stop:
      switch phase {
      case .idle: break
      case .arming: disarm(.escape)
      case .armed, .triggered: disarm(.phone)
      }
      live.ack(c.id)
    case .hush:
      hush()
      live.ack(c.id)
    case .disarm:
      if phase == .triggered { disarm(.phone) }
      live.ack(c.id)
    case .set:
      phoneSet(c)
    case .reset:
      live.ack(c.id) { [weak self] in
        Live.resetLink()
        self?.panel.model.liveLink = Live.link.absoluteString
      }
    }
  }

  private func phoneStart(_ c: PhoneCommand) {
    guard phase == .idle else { return live.ack(c.id, ok: false, why: "busy") }
    guard !screenLocked else { return live.ack(c.id, ok: false, why: "locked") }
    // What the panel's start button needs, checked now: a permission may have been taken away since.
    Preflight.run { [weak self] checks in
      guard let self else { return }
      guard phase == .idle else { return live.ack(c.id, ok: false, why: "busy") }
      guard checks.allSatisfy({ $0.ok || $0.optional }) else { return live.ack(c.id, ok: false, why: "not-ready") }
      applySettings(c)
      if Prefs.veil { panel.close() }
      arm()
      live.ack(c.id)
    }
  }

  /// Between sessions everything may change; while one runs, only the note on the frosted screen.
  private func phoneSet(_ c: PhoneCommand) {
    if phase != .idle, c.place != nil || c.vol != nil || c.test != nil {
      return live.ack(c.id, ok: false, why: "busy")
    }
    applySettings(c)
    if phase == .idle {
      refreshIdle()
    } else {
      live.update { $0.note = Prefs.note }
    }
    live.ack(c.id)
  }

  /// A phone's `start` or `set`: the preferences and the panel take the new values, as a click would.
  private func applySettings(_ c: PhoneCommand) {
    let m = panel.model
    if let place = c.place {
      Prefs.place = place
      m.place = place
    }
    if let note = c.note {
      Prefs.note = note
      m.note = Prefs.note
      if phase != .idle { veil.model.note = Prefs.note }
    }
    if let vol = c.vol {
      Alarm.loudVolume = Float32(vol) / 100
      m.volume = Double(Alarm.loudVolume * 100)
    }
    if let test = c.test {
      Prefs.testMode = test
      m.testMode = test
    }
  }

  /// The owner silenced the alarm from the phone: the beeps or the siren stop, and the Mac stays locked
  /// and keeps filming. Movement after this (a new lift) sounds the siren again.
  private func hush() {
    guard phase == .triggered, let was = stage, was != .hushed else { return }
    let now = Date()
    alarm?.stop()
    alarm = nil
    if was == .soft {
      softTo = now
    } else if let from = sirenFrom {
      sirenSpent += now.timeIntervalSince(from)
      sirenFrom = nil
    }
    stage = .hushed
    hushedAt = now
    motion.settle()
    log("alarm \(was == .soft ? "called off" : "hushed") from the phone")
    live.update(event: was == .soft ? "calledoff" : "hushed", at: now) {
      $0.siren = false
      $0.stage = Stage.hushed.rawValue
      $0.softEnd = nil
    }
  }

  /// After a trigger, every motion sample: whether the Mac is being carried (for the phone), and a lift
  /// or tilt that starts again after a hush.
  private func follow(_ hit: Hit?) {
    let moving = motion.carried
    if moving != carried, Date().timeIntervalSince(carriedAt) >= 2 {  // not every wobble around the threshold
      carried = moving
      carriedAt = Date()
      live.update { $0.carried = moving }
    }
    guard stage == .hushed, let hit, hit.kind == .lifted || hit.kind == .tilted,
          Date().timeIntervalSince(hushedAt) >= GuardApp.hushGrace else { return }
    log("hushed Mac moved again: \(hit.kind.rawValue), \(hit.detail)")
    stage = .siren
    sirenFrom = Date()
    soundAlarm(.loud)
    live.update(event: "lift", key: hit.kind.rawValue) {
      $0.siren = true
      $0.stage = Stage.siren.rawValue
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
        // A loose power strip or a dock renegotiating drops the charger for a moment: only one
        // that stays out counts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
          guard app.phase == .armed, app.armedOnAC, !GuardApp.onAC() else { return }
          app.fire(.charger, "charger unplugged")
        }
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

  /// While a session runs, its phase. Between sessions: the look it waits in for the notice, the
  /// green tick of the landing, the amber pouring out of a cancel, or the outline, with a red dot
  /// for an alarm nobody has looked at yet.
  private func shieldLook() -> StatusIcon.Look {
    switch phase {
    case .arming: return .arming(progress)
    case .armed: return test ? .test : (degraded || recorder == nil) ? .partial : .armed
    case .triggered: return .alarm
    case .idle:
      if let parked { return parked }
      if landing { return .clear }
      if drainLevel > 0 { return .arming(drainLevel) }
      return unseen ? .badge : .idle
    }
  }

  private func render() {
    let tip = switch phase {
    case .idle: unseen ? L("Not guarding · a new alarm to look at") : L("Not guarding")
    case .arming: L("Starting…")
    case .armed: L("Guarding")
    case .triggered: L("Alarm raised")
    }
    item.button?.image = StatusIcon.image(shieldLook(), scale: phase == .idle && landing ? iconScale : 1)
    item.button?.toolTip = tip
    if panel.model.phase != phase { panel.model.phase = phase }
  }

  /// Holds `look` until the notice lands, and never longer than its flight could take.
  private func park(_ look: StatusIcon.Look) {
    parked = look
    parkToken += 1
    let token = parkToken
    DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { [weak self] in
      guard let self, parkToken == token, parked != nil, phase == .idle else { return }
      landed()
    }
  }

  /// The notice reached the shield: green with a tick and a bounce, then the outline 1.6 s later.
  private func landed() {
    parked = nil
    landing = true
    landingToken += 1
    let token = landingToken
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      iconScale = 1
      render()
    } else {
      animateIcon(0.62) { [weak self] p in self?.iconScale = StatusIcon.pop(p) }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
      guard let self, landingToken == token else { return }
      landing = false
      iconScale = 1
      render()
    }
  }

  /// A cancel pours the amber back out of the shield, as the ring unwinds (audit C6).
  private func drain(from level: Double) {
    guard level > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    animateIcon(0.45) { [weak self] p in self?.drainLevel = p >= 1 ? 0 : level * (1 - Ease.retreat(p)) }
  }

  /// Runs `frame` from 0 to 1 over `seconds`, redrawing the shield 60 times a second.
  private func animateIcon(_ seconds: Double, _ frame: @escaping (Double) -> Void) {
    iconTimer?.invalidate()
    let start = CACurrentMediaTime()
    frame(0)
    render()
    let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
      let p = min(1, (CACurrentMediaTime() - start) / seconds)
      frame(p)
      self?.render()
      guard p >= 1 else { return }
      timer.invalidate()
      if self?.iconTimer === timer { self?.iconTimer = nil }
    }
    RunLoop.main.add(t, forMode: .common)
    iconTimer = t
  }

  private func stopIconAnimation() {
    iconTimer?.invalidate()
    iconTimer = nil
    iconScale = 1
    drainLevel = 0
  }
}
