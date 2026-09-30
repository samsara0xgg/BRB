import CoreImage
import Vision

/// Pixellates every face but the largest: whoever is at the laptop is closest to the camera, and
/// people passing behind them stay unrecognizable in the photos, the phone page and the recording.
/// Detection runs on every `every`-th image; in between the last faces are reused, which is close
/// enough at 8 to 15 frames a second and keeps Vision off most frames.
final class Redactor {
  private let every: Int
  private var count = 0
  private var hidden: [CGRect] = []

  init(every: Int = 1) {
    self.every = max(1, every)
  }

  func callAsFunction(_ image: CIImage) -> CIImage {
    if count % every == 0 { hidden = Redactor.bystanders(in: image) }
    count += 1
    return Redactor.pixellate(image, hidden)
  }

  /// Faces other than the largest, in Vision's normalized coordinates (origin bottom-left).
  static func bystanders(in image: CIImage) -> [CGRect] {
    let request = VNDetectFaceRectanglesRequest()
    do { try VNImageRequestHandler(ciImage: image, options: [:]).perform([request]) } catch { return [] }
    let faces = (request.results ?? []).map(\.boundingBox)
    guard faces.count > 1, let largest = faces.max(by: { $0.width * $0.height < $1.width * $1.height }) else { return [] }
    return faces.filter { $0 != largest }
  }

  static func pixellate(_ image: CIImage, _ faces: [CGRect]) -> CIImage {
    guard !faces.isEmpty else { return image }
    let e = image.extent
    var out = image
    for face in faces {
      var box = CGRect(x: e.minX + face.minX * e.width, y: e.minY + face.minY * e.height, width: face.width * e.width, height: face.height * e.height)
      box = box.insetBy(dx: -box.width * 0.25, dy: -box.height * 0.3).intersection(e)  // hair and chin too
      guard !box.isNull, box.width > 1 else { continue }
      let blocks = image.clampedToExtent()
        .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(8, box.width / 7), kCIInputCenterKey: CIVector(x: box.minX, y: box.minY)])
        .cropped(to: box)
      out = blocks.composited(over: out)
    }
    return out
  }
}
