import AppKit
import SwiftUI

setvbuf(stdout, nil, _IOLBF, 0)

private enum LogTime {
  /// One formatter, not one per line (audit L6); a static, so any thread can log.
  static let formatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
  }()
}

func log(_ message: String) {
  print(LogTime.formatter.string(from: Date()), message)
}

/// launchd appends stdout to this file forever: past 10 MB, keep the last 1 MB (audit L8).
func trimLog() {
  let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/guard-mode.log")
  guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue, size > 10_000_000,
        let file = try? FileHandle(forUpdating: url) else { return }
  defer { try? file.close() }
  do {
    try file.seek(toOffset: UInt64(size - 1_000_000))
    var tail = try file.readToEnd() ?? Data()
    if let newline = tail.firstIndex(of: 0x0A) { tail = tail[(newline + 1)...] }  // start on a whole line
    try file.truncate(atOffset: 0)
    try file.write(contentsOf: tail)
    lseek(STDOUT_FILENO, 0, SEEK_END)  // in case launchd opened it without O_APPEND
    log("log trimmed from \(size / 1_000_000) MB")
  } catch {
    log("log not trimmed: \(error)")
  }
}

let args = Array(CommandLine.arguments.dropFirst())
let seconds = args.count > 1 ? Double(args[1]) : nil
switch args.first {
case "selftest": selftest(hardware: !args.contains("--no-hardware"))
case "sensors": sensorsCommand(seconds: seconds ?? 20)
case "keys": keysCommand(seconds: seconds ?? 30)
case "siren": sirenCommand(seconds: seconds ?? 3)
case "record": recordCommand(seconds: seconds ?? 60)
case "camera": cameraCommand(seconds: seconds ?? 40)
case "push": Push.test { exit($0 ? 0 : 1) }; RunLoop.main.run()
case "live": liveCommand(seconds: seconds ?? 60)
case "snapshot": snapshotCommand(args.count > 1 ? args[1] : "armed", out: args.count > 2 && !args[2].hasPrefix("-") ? args[2] : nil)
case nil:
  trimLog()
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let delegate = GuardApp()
  app.delegate = delegate
  app.run()
default:
  print("usage: guard-mode [selftest [--no-hardware] | sensors [s] | keys [s] | siren [s] | record [s] | camera [s] | push | live [s] | snapshot <stage> [png]]")
  exit(2)
}

/// Silent checks: detector decisions on synthetic data, input classification on synthetic (never
/// posted) events, the copy and the history file, and that every piece of hardware the app needs
/// is present. `--no-hardware` skips the hardware, for CI.
func selftest(hardware: Bool) {
  var failures = 0
  func check(_ ok: Bool, _ what: String) {
    print(ok ? "PASS" : "FAIL", what)
    if !ok { failures += 1 }
  }
  let rate = 134.0
  func run(_ samples: [Vec3], _ detector: MotionDetector = MotionDetector()) -> (hit: Hit?, bumps: Int) {
    var d = detector
    for s in samples.prefix(200) { _ = d.feed(s) }
    d.baseline()
    for s in samples.dropFirst(200) {
      if let hit = d.feed(s) { return (hit, d.bumps) }
    }
    return (nil, d.bumps)
  }
  func still(_ n: Int, seed: Int = 0) -> [Vec3] {
    (0..<n).map { i in Vec3(x: 0.001 * sin(Double(i + seed)), y: 0.001 * cos(Double(i * 7 + seed)), z: -1) }
  }
  func knock(_ s: inout [Vec3], at start: Int) {  // measured size, ringing
    for i in 0..<45 { s[start + i].z += 0.85 * exp(-Double(i) / 10) * sin(Double(i) * 1.3) }
  }
  func tilt(_ n: Int, degrees: Double, over secs: Double) -> [Vec3] {
    var s = still(n)
    for i in 300..<n {
      let a = min(Double(i - 300) / (secs * rate), 1) * degrees * .pi / 180
      s[i] = Vec3(x: sin(a), y: 0, z: -cos(a))
    }
    return s
  }
  func carry() -> [Vec3] {
    var s = still(1000)
    for i in 300..<1000 { s[i].z += 0.15 * sin(2 * .pi * 2 * Double(i) / rate) }  // 2 Hz walking sway
    return s
  }
  check(run(still(1000)).hit == nil, "still laptop: no trigger")
  var bump = still(1000)
  for i in 400..<408 { bump[i].z += 0.3 }  // ~60 ms knock on the table
  check(run(bump).hit == nil, "60 ms table bump: no trigger")
  var one = still(1000)
  knock(&one, at: 400)
  check(run(one).hit == nil, "0.85 g ringing knock: no trigger")
  var four = still(1400)
  for k in 0..<4 { knock(&four, at: 400 + k * 40) }
  check(run(four).hit == nil, "four knocks within 1.2 s: no trigger")
  var nudge = still(1400)
  for i in 400..<467 { nudge[i].x += 0.2 * sin(.pi * Double(i - 400) / 67) }  // pushed and settled within 0.5 s
  check(run(nudge).hit == nil, "0.5 s nudge that settles: no trigger")
  // Audit L2: a fast 15° tilt reads as movement too, so the "15° is not enough" case is a slow one.
  check(run(tilt(4000, degrees: 15, over: 20)).hit == nil, "15° tilt over 20 s: no trigger")
  check(run(tilt(1000, degrees: 20, over: 1)).hit != nil, "20° tilt over 1 s: trigger")
  check(run(tilt(3000, degrees: 20, over: 20)).hit?.kind == .tilted, "20° tilt over 20 s: trigger by tilt")
  check(run(carry()).hit?.kind == .lifted, "carried at 2 Hz: trigger as lifted")
  check(run(carry(), Place.transit.motionDetector()).hit == nil, "on the go, swaying: no trigger")
  check(run(tilt(1000, degrees: 25, over: 1), Place.transit.motionDetector()).hit?.kind == .tilted, "on the go, 25° tilt: trigger")
  check(run(carry(), Place.cafe.motionDetector()).hit != nil, "café, carried: trigger")
  check(run(four, Place.cafe.motionDetector()).hit == nil, "café, four knocks: no trigger")
  var apart = still(1600)
  knock(&apart, at: 400)
  knock(&apart, at: 1100)
  let counted = run(apart)
  check(counted.hit == nil && counted.bumps == 2, "two knocks 5 s apart: no trigger, 2 bumps (\(counted.bumps))")

  var lid = LidDetector()
  _ = lid.feed(108)
  lid.baseline()
  check(lid.feed(100) == nil, "lid 108° → 100°: no trigger")
  check(lid.feed(85)?.kind == .lidClosed, "lid 108° → 85°: trigger as closed")
  check(lid.feed(130)?.kind == .lidMoved, "lid 108° → 130°: trigger as moved")

  func sysKey(_ code: Int, subtype: Int16 = 8) -> CGEvent {
    NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                       context: nil, subtype: subtype, data1: code << 16 | 0xA00, data2: -1)!.cgEvent!
  }
  let sys = CGEventType(rawValue: 14)!
  for (code, name) in [(0, "volume up"), (1, "volume down"), (7, "mute"), (2, "brightness up"), (3, "brightness down")] {
    check(InputTap.ownerKey(sys, sysKey(code)) == name, "\(name) key passes")
  }
  check(InputTap.ownerKey(sys, sysKey(16)) == nil, "play/pause key counts as input")
  check(InputTap.ownerKey(sys, sysKey(0, subtype: 1)) == nil, "power key counts as input")
  check(InputTap.ownerKey(.keyDown, CGEvent(keyboardEventSource: nil, virtualKey: 74, keyDown: true)!) == "mute", "mute key code 74 passes")
  check(InputTap.ownerKey(.keyDown, CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!) == nil, "letter key counts as input")
  check(InputTap.ownerKey(.keyDown, CGEvent(keyboardEventSource: nil, virtualKey: 145, keyDown: true)!) == "brightness down", "brightness key code 145 passes")
  let esc = InputTap.input(.keyDown, CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!)
  check(esc.kind == .keyboard && esc.keyCode == 53, "esc is a keyboard input with its key code")
  let click = InputTap.input(.leftMouseDown, CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 40, y: 30), mouseButton: .left)!)
  check(click.kind == .trackpad && click.location == CGPoint(x: 40, y: 30), "click is a trackpad input at the pointer")
  check(InputTap.input(sys, sysKey(0, subtype: 1)).kind == .powerKey, "power key is its own kind")
  check(InputTap.input(sys, sysKey(16)).kind == .keyboard, "media key is a keyboard input")
  check(Trigger.lifted.sirenAtOnce && Trigger.charger.sirenAtOnce && Trigger.powerKey.sirenAtOnce, "taking it: siren at once")
  check(!Trigger.keyboard.sirenAtOnce && !Trigger.trackpad.sirenAtOnce && !Trigger.finger.sirenAtOnce, "touching it: soft stage first")

  let armed = Date(timeIntervalSince1970: 1_790_000_000)
  let session = Session(armed: armed, ended: armed.addingTimeInterval(1500), trigger: .lifted, triggeredAt: armed.addingTimeInterval(900),
                        disarm: .fingerprint, bumps: 1, softSeconds: 0, sirenSeconds: 12, photos: 3, clip: "x.mov", test: false)
  let decoded = (try? JSONEncoder().encode([session])).flatMap { try? JSONDecoder().decode([Session].self, from: $0) }
  check(decoded?.first?.trigger == .lifted && decoded?.first?.photos == 3 && decoded?.first?.disarm == .fingerprint, "history entry round-trips")
  check(session.welcome.alarmed && session.welcome.chips.count == 2 && !session.line.isEmpty, "welcome after an alarm: title, two chips")
  var quiet = session
  quiet.trigger = nil
  quiet.bumps = 0
  check(!quiet.welcome.alarmed && quiet.welcome.chips.count == 2, "welcome after a quiet run: two chips")

  let looks: [StatusIcon.Look] = [.idle, .arming(0.4), .armed, .alarm, .test, .partial]
  check(looks.allSatisfy { StatusIcon.image($0).cgImage(forProposedRect: nil, context: nil, hints: nil) != nil }, "menu-bar shield draws in all six looks")
  check(StatusIcon.image(.idle).isTemplate && !StatusIcon.image(.armed).isTemplate, "only the idle shield follows the menu bar's color")
  check(Ease.fog(0) == 0 && Ease.fog(1) == 1 && Ease.fog(0.5) > 0.5 && Ease.melt(0.25) < Ease.melt(0.75), "timing curves")

  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("guard-mode-selftest-\(getpid())")
  try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  func clip(_ name: String, daysOld: Double, bytes: Int) -> URL {
    let url = dir.appendingPathComponent(name + ".mov")
    FileManager.default.createFile(atPath: url.path, contents: Data(count: bytes))
    try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-daysOld * 86400)], ofItemAtPath: url.path)
    return url
  }
  let old = clip("old", daysOld: 8, bytes: 10), a = clip("a", daysOld: 3, bytes: 10), b = clip("b", daysOld: 2, bytes: 10), c = clip("c", daysOld: 1, bytes: 10)
  Recorder.prune(in: dir, cap: 25)
  let exists = { (u: URL) in FileManager.default.fileExists(atPath: u.path) }
  check(!exists(old) && !exists(a) && exists(b) && exists(c), "recordings: older than 7 days deleted, then the oldest past the size cap")
  try? FileManager.default.removeItem(at: dir)

  let zh = Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "zh-Hans")
  let zhTable = zh.flatMap { NSDictionary(contentsOfFile: $0) as? [String: String] }
  check(zhTable?["Alarm raised"] == "已报警", "Chinese copy is in the app (\(zhTable?.count ?? 0) strings)")
  check(L("Alarm raised") == "Alarm raised" || L("Alarm raised") == "已报警", "copy resolves in this Mac's language: \(L("Alarm raised"))")

  if hardware {
    print("INFO power source: \(GuardApp.onAC() ? "charger" : "battery")")
    print("INFO alarm volume \(Alarm.loudVolume), test mode \(Prefs.testMode ? "on" : "off")")
    let speakers = Alarm.builtInSpeakers()
    check(speakers != nil, "built-in speakers: \(speakers.map { "\(Alarm.name($0)) (\(Alarm.uid($0))), volume \(Alarm.volume($0))" } ?? "none")")
    check(Recorder.camera != nil, "built-in camera: \(Recorder.camera?.localizedName ?? "none")")
    print("INFO camera hardware streaming now: \(Recorder.hardwareStreaming ? "yes" : "no")")
    check(GuardApp.lockScreen != nil, "lock-screen function resolves (not called)")
    print("INFO built-in screen: \(NSScreen.screens.contains { $0.isBuiltIn } ? "yes" : "no"), \(NSScreen.screens.count) screen(s)")
    let sensors = Sensors()
    sensors.start()
    RunLoop.main.run(until: Date().addingTimeInterval(1.5))
    check(sensors.accelReports > 100, "accelerometer streams: \(sensors.accelReports) reports in 1.5 s")
    check(sensors.lidReports > 0, "lid angle streams: \(sensors.lidReports) reports")
    sensors.stop()
  }
  print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
  exit(failures == 0 ? 0 : 1)
}

/// Live lid angle and motion readings plus what the detectors decide, for calibrating the knobs.
func sensorsCommand(seconds: Double) {
  let sensors = Sensors()
  var motion = Prefs.place.motionDetector(), lid = LidDetector()
  var peak = 0.0, baselined = false
  sensors.onAccel = { a in
    if let g = motion.gravity { peak = max(peak, (a - g).length) }
    if let hit = motion.feed(a), baselined { log("MOTION TRIGGER: \(hit.kind.rawValue), \(hit.detail)") }
  }
  sensors.onLid = { angle in if let hit = lid.feed(angle), baselined { log("LID TRIGGER: \(hit.kind.rawValue), \(hit.detail)") } }
  sensors.start()
  let start = Date()
  log("place: \(Prefs.place.rawValue)")
  Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    let t = Date().timeIntervalSince(start)
    if !baselined && t >= 1.5 { motion.baseline(); lid.baseline(); baselined = true; log("baseline captured") }
    log(String(format: "lid %@  accel reports %d  peak dynamic %.4fg  bumps %d", lid.last.map { String(format: "%.0f°", $0) } ?? "-",
               sensors.accelReports, peak, motion.bumps))
    peak = 0
    if t >= seconds { exit(0) }
  }
  RunLoop.main.run()
}

/// Raw accelerometer and lid samples as CSV on stdout (t, x, y, z in g, lid in degrees), for tuning
/// the detectors offline against real knocks and lifts.
func recordCommand(seconds: Double) {
  let sensors = Sensors()
  let start = Date()
  var lidAngle = 0.0
  print("t,x,y,z,lid")
  sensors.onLid = { lidAngle = $0 }
  sensors.onAccel = { a in print(String(format: "%.4f,%.5f,%.5f,%.5f,%.0f", Date().timeIntervalSince(start), a.x, a.y, a.z, lidAngle)) }
  sensors.start()
  DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
  RunLoop.main.run()
}

/// Buffers like an armed session, saves halfway as a trigger would, and prints the state every
/// second (silent): nothing may reach the disk before the save.
func cameraCommand(seconds: Double) {
  let r = Recorder()
  do { try r.start() } catch { print("camera failed: \(error)"); exit(1) }
  let start = Date()
  var saved = false
  Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    log(r.status)
    let t = Date().timeIntervalSince(start)
    if !saved && t >= seconds / 2 {
      saved = true
      let url = r.save { photo in log("first photo: \(photo.map { "\($0.count / 1024) KB" } ?? "none")") }
      log("saving to \(url.lastPathComponent)")
    }
    if t >= seconds {
      r.stop { exit(0) }
    }
  }
  RunLoop.main.run()
}

/// Prints how each real key / trackpad event would be treated while armed. Uses the same active
/// tap as the armed app (so an input method cannot hide from it), but never swallows anything.
func keysCommand(seconds: Double) {
  let tap = InputTap()
  guard tap.start() else { print("event tap refused: grant Accessibility to this terminal"); exit(1) }
  tap.onInput = { input in if !input.what.hasPrefix("trackpad") { log("TRIGGER  \(input.kind.rawValue): \(input.what)") } }
  log("press keys / touch the trackpad; owner keys (volume, mute, brightness) should show nothing")
  DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
  RunLoop.main.run()
}

/// Camera on and connected to the relay for `seconds` with live frames allowed, as after a trigger,
/// without recording or guarding: prints the owner's link, for checking the phone page (silent).
func liveCommand(seconds: Double) {
  let camera = Recorder()
  do { try camera.start() } catch { print("camera failed: \(error)"); exit(1) }
  camera.allowLive()
  let live = Live()
  live.start(camera, state: LiveState(phase: "armed", since: LiveState.ms(Date()), place: Prefs.place.rawValue, note: Prefs.note, camera: true))
  log("phone page at \(Live.link.absoluteString)")
  DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    live.stop()
    camera.stop { exit(0) }
  }
  RunLoop.main.run()
}

/// Plays the soft stage, then the loud siren, then restores the volume. Makes real noise.
func sirenCommand(seconds: Double) {
  guard let alarm = Alarm() else { print("no built-in speakers"); exit(1) }
  do {
    try alarm.play(.soft)
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    try alarm.play(.loud)
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
  } catch {
    print("alarm failed: \(error)")
  }
  alarm.stop()
  exit(0)
}

/// Shows the frosted screen at one stage, or the panel, for 3.5 s without guarding anything (silent):
/// for screenshots. With `out`, also renders the notice or the panel to that PNG (SwiftUI only, so
/// without the blur behind it). Run with `-AppleLanguages "(zh-Hans)"` for the Chinese copy.
func snapshotCommand(_ what: String, out: String?) {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let zh = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") == true
  let veil = Veil()
  let m = veil.model
  m.note = zh ? "3 点回来" : "Back at 3"
  m.armedAt = Date().addingTimeInterval(-42 * 60)
  m.pushOn = true
  let armed = Date().addingTimeInterval(-40 * 60)
  let alarmed = Session(armed: armed, ended: Date(), trigger: .lifted, triggeredAt: armed.addingTimeInterval(1500), disarm: .fingerprint,
                        bumps: 0, softSeconds: 0, sirenSeconds: 8, photos: 3, clip: "x.mov", test: false)
  let quiet = Session(armed: armed.addingTimeInterval(-86400), ended: armed.addingTimeInterval(-86400 + 1500), trigger: nil, triggeredAt: nil,
                      disarm: .fingerprint, bumps: 2, softSeconds: 0, sirenSeconds: 0, photos: 0, clip: nil, test: false)
  var panel: PanelModel?
  var window: NSWindow?
  switch what {
  case "countdown":
    veil.countdown(5)
    for s in 1...3 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(s)) { m.remaining = 5 - s } }
  case "armed", "test":
    m.test = what == "test"
    veil.guarding()
  case "alarm":
    veil.guarding()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { veil.alarm(pointer: nil, origin: Trigger.keyboard.floodOrigin) }
  case "welcome":
    veil.guarding()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { veil.welcome(alarmed.welcome, toward: nil) }
  case "panel", "notready":
    let p = PanelModel()
    p.refresh()
    if what == "notready" { p.page = .notReady }
    p.recent = [alarmed, quiet]
    p.clips = 2
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      if what == "panel" { p.checks = p.checks.map { Check(id: $0.id, title: $0.title, detail: $0.detail, ok: true, optional: $0.optional, quiet: $0.quiet) } }
      if what == "notready" {  // one thing to fix, whatever this Mac has
        p.checks = p.checks.map { $0.id == .sleep ? Check(id: .sleep, title: $0.title, detail: L("Needs an admin rule, installed once from Terminal"), ok: false) : $0 }
      }
    }
    let host = NSHostingController(rootView: PanelView(model: p))
    host.sizingOptions = .preferredContentSize
    let w = NSWindow(contentViewController: host)
    w.styleMask = [.titled, .fullSizeContentView]
    w.titlebarAppearsTransparent = true
    w.titleVisibility = .hidden
    for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] { w.standardWindowButton(b)?.isHidden = true }
    let pin = {  // where the popover hangs, under the menu bar, again once the checks change its height
      if let area = NSScreen.main?.visibleFrame { w.setFrameTopLeftPoint(NSPoint(x: area.maxX - w.frame.width - 160, y: area.maxY - 6)) }
    }
    pin()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: pin)
    w.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    panel = p
    window = w
  default:
    print("snapshot countdown | armed | test | alarm | welcome | panel | notready [out.png]")
    exit(2)
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
    guard let out else { return }
    let size = NSScreen.screens.first { $0.isBuiltIn }?.frame.size ?? NSScreen.main?.frame.size ?? CGSize(width: 1512, height: 982)
    let view: AnyView = if let panel {
      AnyView(PanelView(model: panel).background(Color(nsColor: .windowBackgroundColor)))
    } else {
      AnyView(VeilView(model: m, showsNotice: true, displayID: 0)
        .frame(width: size.width, height: size.height)
        .background(LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.3), Color(red: 0.05, green: 0.07, blue: 0.12)], startPoint: .top, endPoint: .bottom)))
    }
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
      print("render failed")
      return
    }
    try? png.write(to: URL(fileURLWithPath: out))
    log("rendered \(what) to \(out)")
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
    _ = window
    exit(0)
  }
  app.run()
}
