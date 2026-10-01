import AVFoundation
import CoreImage
import IOKit

/// The built-in camera, recording only when someone touches the Mac. From the countdown on it keeps
/// the last 10 s in memory (8 small JPEGs a second) and nothing on disk: walking past an armed Mac
/// leaves no trace. `save` writes those 10 s and everything after them to
/// ~/Movies/BRB/<time>.mov until `stop`, and hands out the newest frame as the first photo.
/// Every photo, live frame and movie frame has bystanders' faces pixellated (`Redactor`).
final class Recorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/BRB")
  static let ringSeconds = 10.0
  private let session = AVCaptureSession()
  private let frames = AVCaptureVideoDataOutput()
  private let queue = DispatchQueue(label: "brb.frames")
  // The frame queue's own state.
  private var ring: [(t: Double, jpeg: Data)] = []
  private var lastRing = -1.0, lastMovie = -1.0, lastLive = -1.0
  private var saving = false
  private var liveAllowed = false
  private var movie: Movie?
  private var movieURL: URL?
  private var wantPhoto: [(Data?) -> Void] = []
  private var liveFrame: ((Data) -> Void)?
  private lazy var images = CIContext()
  private let photoRedactor = Redactor()
  private let liveRedactor = Redactor(every: 2)
  private let movieRedactor = Redactor(every: 4)
  // Main queue.
  private var observers: [NSObjectProtocol] = []
  private var counted = false

  /// Recorders with the camera on in this process (main queue).
  private(set) static var running = 0

  /// The built-in camera hardware is streaming, whoever asked for it (what the green light shows).
  static var hardwareStreaming: Bool {
    IORegistryEntrySearchCFProperty(IORegistryGetRootEntry(kIOMainPortDefault), kIOServicePlane, "FrontCameraStreaming" as CFString,
                                    nil, IOOptionBits(kIORegistryIterateRecursively)) as? Bool ?? false
  }

  static var camera: AVCaptureDevice? {
    AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.first
  }

  /// Camera on, the last 10 s kept in memory only.
  func start() throws {
    guard let camera = Recorder.camera else { throw GuardError(L("No built-in camera found")) }
    let input = try AVCaptureDeviceInput(device: camera)
    session.beginConfiguration()
    if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
    guard session.canAddInput(input), session.canAddOutput(frames) else { throw GuardError("camera cannot join the capture session") }
    session.addInput(input)
    frames.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    frames.alwaysDiscardsLateVideoFrames = true
    session.addOutput(frames)
    frames.setSampleBufferDelegate(self, queue: queue)
    session.commitConfiguration()
    for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: .main) { n in
        log("camera: \(n.name.rawValue) \(n.userInfo ?? [:])")  // a shut lid pauses the frames; they resume on their own
      })
    }
    session.startRunning()
    Recorder.running += 1
    counted = true
  }

  /// Someone touched it. Returns the movie's file; `firstPhoto` gets the newest frame on the main
  /// queue (or the next one, when the buffer is empty).
  func save(firstPhoto: @escaping (Data?) -> Void) -> URL {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH.mm.ss"
    let url = Recorder.folder.appendingPathComponent(f.string(from: Date()) + ".mov")
    try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
    queue.async {
      self.saving = true
      self.liveAllowed = true
      self.movieURL = url
      let buffered = self.ring
      self.ring.removeAll()
      if let newest = buffered.last.flatMap({ CIImage(data: $0.jpeg) }) {
        let photo = self.photoJPEG(self.photoRedactor(newest))
        DispatchQueue.main.async { firstPhoto(photo) }
      } else {
        self.photo(firstPhoto)
      }
      for frame in buffered {
        guard let image = CIImage(data: frame.jpeg) else { continue }
        self.write(image, at: frame.t)
      }
      log("saving: \(buffered.count) buffered frames written to \(url.lastPathComponent)")
    }
    return url
  }

  /// Live frames without saving, for the `live` command.
  func allowLive() {
    queue.async { self.liveAllowed = true }
  }

  /// The next frame as a JPEG of at most 200 KB, bystanders pixellated, on the main queue; nil when
  /// none arrives within 1.5 s (lid shut, camera off).
  func photo(_ done: @escaping (Data?) -> Void) {
    queue.async {
      var finished = false
      let finish = { (jpeg: Data?) in
        guard !finished else { return }
        finished = true
        DispatchQueue.main.async { done(jpeg) }
      }
      self.wantPhoto.append(finish)
      self.queue.asyncAfter(deadline: .now() + 1.5) { finish(nil) }
    }
  }

  /// While set, and only after `save` (a trigger), gets a half-size JPEG about 8 times a second.
  func setLive(_ handler: ((Data) -> Void)?) {
    queue.async { self.liveFrame = handler }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
    let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
    let image = CIImage(cvPixelBuffer: pixels)
    if !wantPhoto.isEmpty {
      let waiting = wantPhoto
      wantPhoto.removeAll()
      let photo = photoJPEG(photoRedactor(image))
      waiting.forEach { $0(photo) }
    }
    if saving {
      if t - lastMovie >= 1.0 / 15 {
        lastMovie = t
        write(image, at: t)
      }
    } else if t - lastRing >= 1.0 / 8 {
      lastRing = t
      if let jpeg = jpeg(image, quality: 0.55) { ring.append((t, jpeg)) }
      while let first = ring.first, t - first.t > Recorder.ringSeconds { ring.removeFirst() }
    }
    if liveAllowed, let live = liveFrame, t - lastLive >= 0.12 {
      lastLive = t
      let small = liveRedactor(image).transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
      if let frame = jpeg(small, quality: 0.5) { live(frame) }
    }
  }

  private func write(_ image: CIImage, at t: Double) {
    if movie == nil, let url = movieURL {
      do {
        movie = try Movie(url: url, size: image.extent.size, context: images)
      } catch {
        log("movie not started: \(error)")
        movieURL = nil
      }
    }
    movie?.append(movieRedactor(image), at: t)
  }

  private func jpeg(_ image: CIImage, quality: CGFloat) -> Data? {
    images.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
  }

  /// Small enough for the push and the relay: 200 KB at most.
  private func photoJPEG(_ image: CIImage) -> Data? {
    guard let first = jpeg(image, quality: 0.55) else { return nil }
    if first.count <= 200_000 { return first }
    if let second = jpeg(image, quality: 0.4), second.count <= 200_000 { return second }
    return jpeg(image.transformed(by: CGAffineTransform(scaleX: 0.7, y: 0.7)), quality: 0.4)
  }

  var status: String {
    queue.sync {
      String(format: "buffered %d frames, saving %@, movie %d frames", ring.count, saving ? "yes" : "no", movie?.frames ?? 0)
    }
  }

  /// Camera off; the movie, if any, is finished and `done` runs on the main queue.
  func stop(_ done: (() -> Void)? = nil) {
    if counted { Recorder.running -= 1 }
    counted = false
    session.stopRunning()
    observers.forEach(NotificationCenter.default.removeObserver)
    observers.removeAll()
    queue.async {
      self.ring.removeAll()
      self.liveFrame = nil
      self.saving = false
      self.liveAllowed = false
      let movie = self.movie
      self.movie = nil
      self.movieURL = nil
      guard let movie else { DispatchQueue.main.async { done?() }; return }
      movie.finish { ok in
        log("recording \(ok ? "saved" : "failed"): \(movie.url.lastPathComponent), \(movie.frames) frames")
        DispatchQueue.main.async { done?() }
      }
    }
  }

  /// Recordings in the folder.
  static func clips() -> Int {
    ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "mov" }.count
  }

  /// Recordings are kept for 7 days (Allen, 2026-09-24) and 20 GB at most, oldest deleted first; at
  /// launch and at arming.
  static func prune(in folder: URL = Recorder.folder, now: Date = Date(), cap: Int64 = 20_000_000_000) {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
    let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [])
      .filter { $0.pathExtension == "mov" }
      .compactMap { url -> (url: URL, date: Date, size: Int64)? in
        guard let v = try? url.resourceValues(forKeys: Set(keys)), let d = v.contentModificationDate else { return nil }
        return (url, d, Int64(v.fileSize ?? 0))
      }
      .sorted { $0.date > $1.date }
    let cutoff = now.addingTimeInterval(-7 * 86400)
    var total: Int64 = 0
    for f in files {
      total += f.size
      guard f.date < cutoff || total > cap else { continue }
      try? FileManager.default.removeItem(at: f.url)
      log("deleted recording \(f.url.lastPathComponent): \(f.date < cutoff ? "older than 7 days" : "over 20 GB in all")")
    }
  }
}

/// A .mov written frame by frame. A fragment is written every 2 s, so a killed process still
/// leaves a playable file.
private final class Movie {
  let url: URL
  private(set) var frames = 0
  private let writer: AVAssetWriter
  private let input: AVAssetWriterInput
  private let adaptor: AVAssetWriterInputPixelBufferAdaptor
  private let context: CIContext
  private var start: Double?
  private var last = -1.0

  init(url: URL, size: CGSize, context: CIContext) throws {
    self.url = url
    self.context = context
    let w = Int(size.width) & ~1, h = Int(size.height) & ~1
    writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
    var settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: w, AVVideoHeightKey: h]
    if !writer.canApply(outputSettings: settings, forMediaType: .video) { settings[AVVideoCodecKey] = AVVideoCodecType.h264 }
    input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = true
    adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: w,
      kCVPixelBufferHeightKey as String: h,
    ])
    guard writer.canAdd(input) else { throw GuardError("movie writer refused the video input") }
    writer.add(input)
    guard writer.startWriting() else { throw writer.error ?? GuardError("movie writer did not start") }
    writer.startSession(atSourceTime: .zero)
  }

  /// `t` in seconds on any clock; the movie starts at the first frame and times only go forward.
  func append(_ image: CIImage, at t: Double) {
    guard writer.status == .writing else { return }
    let t0 = start ?? t
    start = t0
    var s = t - t0
    if s <= last { s = last + 0.001 }
    var waited = 0.0
    while !input.isReadyForMoreMediaData && waited < 0.5 {
      Thread.sleep(forTimeInterval: 0.01)
      waited += 0.01
    }
    guard input.isReadyForMoreMediaData, let pool = adaptor.pixelBufferPool else { return }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else { return }
    context.render(image, to: buffer)
    if adaptor.append(buffer, withPresentationTime: CMTime(seconds: s, preferredTimescale: 600)) {
      last = s
      frames += 1
    }
  }

  func finish(_ done: @escaping (Bool) -> Void) {
    guard writer.status == .writing else { done(false); return }
    input.markAsFinished()
    writer.finishWriting { done(self.writer.status == .completed) }
  }
}
