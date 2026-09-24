import AppKit

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ message: String) {
  let f = DateFormatter()
  f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
  print(f.string(from: Date()), message)
}

let args = Array(CommandLine.arguments.dropFirst())
let seconds = args.count > 1 ? Double(args[1]) : nil
switch args.first {
case "selftest": selftest()
case "sensors": sensorsCommand(seconds: seconds ?? 20)
case "keys": keysCommand(seconds: seconds ?? 30)
case "siren": sirenCommand(seconds: seconds ?? 3)
case "record": recordCommand(seconds: seconds ?? 60)
case "camera": cameraCommand(seconds: seconds ?? 40)
case "push": Push.test { exit($0 ? 0 : 1) }; RunLoop.main.run()
case nil:
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let delegate = GuardApp()
  app.delegate = delegate
  app.run()
default:
  print("usage: guard-mode [selftest | sensors [s] | keys [s] | siren [s] | record [s] | camera [s] | push]")
  exit(2)
}

/// Silent checks: detector decisions on synthetic data, owner-key classification on synthetic
/// (never posted) events, and that every piece of hardware the app needs is present.
func selftest() {
  var failures = 0
  func check(_ ok: Bool, _ what: String) {
    print(ok ? "PASS" : "FAIL", what)
    if !ok { failures += 1 }
  }
  let rate = 134.0
  func run(_ samples: [Vec3]) -> String? {
    var d = MotionDetector()
    for s in samples.prefix(200) { _ = d.feed(s) }
    d.baseline()
    return samples.dropFirst(200).lazy.compactMap { d.feed($0) }.first
  }
  func still(_ n: Int, seed: Int = 0) -> [Vec3] {
    (0..<n).map { i in Vec3(x: 0.001 * sin(Double(i + seed)), y: 0.001 * cos(Double(i * 7 + seed)), z: -1) }
  }
  check(run(still(1000)) == nil, "still laptop: no trigger")
  var bump = still(1000)
  for i in 400..<408 { bump[i].z += 0.3 }  // ~60 ms knock on the table
  check(run(bump) == nil, "60 ms table bump: no trigger")
  var knock = still(1000)
  for i in 0..<45 { knock[400 + i].z += 0.85 * exp(-Double(i) / 10) * sin(Double(i) * 1.3) }  // measured-size knock, ringing
  check(run(knock) == nil, "0.85 g ringing knock: no trigger")
  var knocks = still(1400)
  for k in 0..<4 { for i in 0..<45 { knocks[400 + k * 40 + i].z += 0.85 * exp(-Double(i) / 10) * sin(Double(i) * 1.3) } }
  check(run(knocks) == nil, "four knocks within 1.2 s: no trigger")
  var nudge = still(1400)
  for i in 400..<467 { nudge[i].x += 0.2 * sin(.pi * Double(i - 400) / 67) }  // pushed and settled within 0.5 s
  check(run(nudge) == nil, "0.5 s nudge that settles: no trigger")
  var tilt = still(1000)
  for i in 300..<1000 {
    let a = min(Double(i - 300) / rate, 1) * 15 * .pi / 180  // tilt 15° over 1 s
    tilt[i] = Vec3(x: sin(a), y: 0, z: -cos(a))
  }
  for i in 300..<1000 {
    let a = min(Double(i - 300) / rate, 1) * 20 * .pi / 180  // tilt 20° over 1 s: someone turns it
    tilt[i] = Vec3(x: sin(a), y: 0, z: -cos(a))
  }
  check(run(tilt) != nil, "20° tilt over 1 s: trigger")
  var slow = still(3000)
  for i in 300..<3000 {
    let a = min(Double(i - 300) / (20 * rate), 1) * 20 * .pi / 180  // tilt 20° over 20 s, too slow to shake
    slow[i] = Vec3(x: sin(a), y: 0, z: -cos(a))
  }
  check(run(slow)?.contains("倾斜") == true, "20° tilt over 20 s: trigger by tilt")
  var carry = still(1000)
  for i in 300..<1000 { carry[i].z += 0.15 * sin(2 * .pi * 2 * Double(i) / rate) }  // 2 Hz walking sway
  check(run(carry)?.contains("晃动") == true, "carried at 2 Hz: trigger")
  var lid = LidDetector()
  _ = lid.feed(108)
  lid.baseline()
  check(lid.feed(100) == nil, "lid 108° → 100°: no trigger")
  check(lid.feed(85) != nil, "lid 108° → 85°: trigger")

  func sysKey(_ code: Int, subtype: Int16 = 8) -> CGEvent {
    NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                       context: nil, subtype: subtype, data1: code << 16 | 0xA00, data2: -1)!.cgEvent!
  }
  let sys = CGEventType(rawValue: 14)!
  for (code, name) in [(0, "音量+"), (1, "音量-"), (7, "静音"), (2, "亮度+"), (3, "亮度-")] {
    check(InputTap.ownerKey(sys, sysKey(code)) == name, "\(name) key passes")
  }
  check(InputTap.ownerKey(sys, sysKey(16)) == nil, "play/pause key counts as input")
  check(InputTap.ownerKey(sys, sysKey(0, subtype: 1)) == nil, "power key counts as input")
  check(InputTap.ownerKey(.keyDown, CGEvent(keyboardEventSource: nil, virtualKey: 74, keyDown: true)!) == "静音", "mute key code 74 passes")
  check(InputTap.ownerKey(.keyDown, CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!) == nil, "letter key counts as input")
  check(InputTap.ownerKey(.keyDown, CGEvent(keyboardEventSource: nil, virtualKey: 145, keyDown: true)!) == "亮度-", "brightness key code 145 passes")

  print("INFO power source: \(GuardApp.onAC() ? "charger" : "battery")")
  try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
  let old = Recorder.folder.appendingPathComponent("selftest-old.mov"), fresh = Recorder.folder.appendingPathComponent("selftest-fresh.mov")
  FileManager.default.createFile(atPath: old.path, contents: Data())
  FileManager.default.createFile(atPath: fresh.path, contents: Data())
  try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 86400)], ofItemAtPath: old.path)
  Recorder.pruneOld()
  check(!FileManager.default.fileExists(atPath: old.path) && FileManager.default.fileExists(atPath: fresh.path), "recordings older than 7 days deleted, newer kept")
  try? FileManager.default.removeItem(at: fresh)
  print("INFO alarm volume setting \(Alarm.loudVolume)" + (Alarm.loudVolume == 0 ? " (silent test mode)" : ""))
  let speakers = Alarm.builtInSpeakers()
  check(speakers != nil, "built-in speakers: \(speakers.map { "\(Alarm.name($0)), volume \(Alarm.volume($0))" } ?? "none")")
  check(Recorder.camera != nil, "built-in camera: \(Recorder.camera?.localizedName ?? "none")")
  check(GuardApp.lockScreen != nil, "lock-screen function resolves (not called)")

  let sensors = Sensors()
  sensors.start()
  RunLoop.main.run(until: Date().addingTimeInterval(1.5))
  check(sensors.accelReports > 100, "accelerometer streams: \(sensors.accelReports) reports in 1.5 s")
  check(sensors.lidReports > 0, "lid angle streams: \(sensors.lidReports) reports")
  sensors.stop()
  print(failures == 0 ? "ALL PASS" : "\(failures) FAILED")
  exit(failures == 0 ? 0 : 1)
}

/// Live lid angle and motion readings plus what the detectors decide, for calibrating the knobs.
func sensorsCommand(seconds: Double) {
  let sensors = Sensors()
  var motion = MotionDetector(), lid = LidDetector()
  var peak = 0.0, baselined = false
  sensors.onAccel = { a in
    if let g = motion.gravity { peak = max(peak, (a - g).length) }
    if let why = motion.feed(a), baselined { log("MOTION TRIGGER: \(why)") }
  }
  sensors.onLid = { angle in if let why = lid.feed(angle), baselined { log("LID TRIGGER: \(why)") } }
  sensors.start()
  let start = Date()
  Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    let t = Date().timeIntervalSince(start)
    if !baselined && t >= 1.5 { motion.baseline(); lid.baseline(); baselined = true; log("baseline captured") }
    log(String(format: "lid %@  accel reports %d  peak dynamic %.4fg", lid.last.map { String(format: "%.0f°", $0) } ?? "-", sensors.accelReports, peak))
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

/// Records like an armed session and prints the movie output's state every second (silent), to see
/// what a lid close and reopen does to the recording.
func cameraCommand(seconds: Double) {
  let r = Recorder()
  do { log("recording to \(try r.start().lastPathComponent)") } catch { print("camera failed: \(error)"); exit(1) }
  let start = Date()
  Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    log(r.status)
    if Date().timeIntervalSince(start) >= seconds {
      r.stop()
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }  // let the finish callback land
    }
  }
  RunLoop.main.run()
}

/// Prints how each real key / trackpad event would be treated while armed. Uses the same active
/// tap as the armed app (so an input method cannot hide from it), but never swallows anything.
func keysCommand(seconds: Double) {
  let tap = InputTap()
  guard tap.start() else { print("event tap refused: grant Accessibility to this terminal"); exit(1) }
  tap.onInput = { what in if !what.hasPrefix("触控板") { log("TRIGGER  \(what)") } }
  log("press keys / touch the trackpad; owner keys (volume, mute, brightness) should show nothing")
  DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
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
