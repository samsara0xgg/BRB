import Foundation

/// install.sh's LaunchAgent opens BRB again after a crash, a `kill -9` or an `exit(1)` (which the
/// app uses to get a fresh camera or event tap), and `resume()` then picks the session up or puts
/// the Mac back (sleep, volume). The copy dragged into Applications runs as a login item, which
/// nothing restarts: it stayed down after the first such exit, offline on the phone and maybe with
/// the Mac kept awake. For that copy a small shell waits for the app to end and opens it again,
/// unless the app ended on purpose (Quit, SIGTERM, logout), which removes the flag first.
enum Relaunch {
  /// Holds the pid of the app the shell watches; gone after a clean exit.
  static let flag = GuardApp.supportDir.appendingPathComponent("running")

  /// The shell: wait for the app, open it again if it did not stand down, no faster than every 10 s
  /// when it keeps dying at launch. Arguments: the pid, the flag, the app bundle.
  private static let script = """
    pid=$1 flag=$2 app=$3 start=$(date +%s)
    while kill -0 "$pid" 2>/dev/null; do sleep 1; done
    [ "$(cat "$flag" 2>/dev/null)" = "$pid" ] || exit 0
    [ $(( $(date +%s) - start )) -lt 10 ] && sleep 10
    open "$app"
    """

  static func watch() {
    // launchd puts the job's label here for install.sh's agent, which restarts BRB itself.
    guard ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] != "com.allen.guard-mode" else { return }
    let pid = String(getpid())
    do {
      try FileManager.default.createDirectory(at: GuardApp.supportDir, withIntermediateDirectories: true)
      try pid.write(to: flag, atomically: true, encoding: .utf8)
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/bin/sh")
      p.arguments = ["-c", script, "brb-relaunch", pid, flag.path, Bundle.main.bundlePath]
      p.standardInput = FileHandle.nullDevice
      p.standardOutput = FileHandle.nullDevice
      p.standardError = FileHandle.nullDevice
      try p.run()
      log("relaunch watcher started")
    } catch {
      log("relaunch watcher not started: \(error)")
    }
  }

  /// Ending on purpose: the shell lets the app go.
  static func standDown() {
    try? FileManager.default.removeItem(at: flag)
  }
}
