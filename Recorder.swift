import AVFoundation

/// Records the built-in camera (720p, no audio) to ~/Movies/GuardMode/<start time>.mov for the whole
/// armed session. The movie output writes a fragment every 10 s, so a killed process still leaves a
/// playable file.
final class Recorder: NSObject, AVCaptureFileOutputRecordingDelegate {
  static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/GuardMode")
  private let session = AVCaptureSession()
  private let output = AVCaptureMovieFileOutput()
  private var observers: [NSObjectProtocol] = []
  private var active = false

  static var camera: AVCaptureDevice? {
    AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.first
  }

  func start() throws -> URL {
    guard let camera = Recorder.camera else { throw GuardError("找不到内置摄像头") }
    let input = try AVCaptureDeviceInput(device: camera)
    session.beginConfiguration()
    if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
    guard session.canAddInput(input), session.canAddOutput(output) else { throw GuardError("摄像头无法加入录像会话") }
    session.addInput(input)
    session.addOutput(output)
    session.commitConfiguration()
    for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { [weak self] n in
        log("camera: \(n.name.rawValue) \(n.userInfo ?? [:])")
        // An interruption (lid shut, lock) ends the movie; carry on in a new file once it is over.
        guard let self, n.name == AVCaptureSession.interruptionEndedNotification, active, !output.isRecording else { return }
        log("recording resumed to \(newFile().lastPathComponent)")
      })
    }
    session.startRunning()
    try FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
    active = true
    return newFile()
  }

  private func newFile() -> URL {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH.mm.ss"
    let url = Recorder.folder.appendingPathComponent(f.string(from: Date()) + ".mov")
    output.startRecording(to: url, recordingDelegate: self)
    return url
  }

  /// Recordings are kept for 7 days (Allen, 2026-09-24); older ones are deleted at launch and at arming.
  static func pruneOld(now: Date = Date()) {
    let cutoff = now.addingTimeInterval(-7 * 86400)
    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    for url in files where url.pathExtension == "mov" {
      guard let d = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d < cutoff else { continue }
      try? FileManager.default.removeItem(at: url)
      log("deleted recording older than 7 days: \(url.lastPathComponent)")
    }
  }

  var status: String {
    String(format: "recording=%@ duration=%.1fs suspended=%@", output.isRecording ? "yes" : "no",
           output.recordedDuration.seconds, (Recorder.camera?.isSuspended ?? false) ? "yes" : "no")
  }

  func stop() {
    active = false
    output.stopRecording()
    session.stopRunning()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
  }

  func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
    log("recording finished: \(url.lastPathComponent)" + (error.map { " (\($0.localizedDescription))" } ?? ""))
  }
}
