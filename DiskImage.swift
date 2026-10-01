import AppKit

/// The background of BRB.dmg's window: where to drag the app, in both languages. Drawn here rather
/// than checked in as a picture, so the words and the layout live next to the icon positions
/// (scripts/dmg-settings.py places the icons at `app` and `applications`).
enum DiskImage {
  static let size = CGSize(width: 640, height: 400)
  static let app = CGPoint(x: 170, y: 200)  // icon centres, from the top left
  static let applications = CGPoint(x: 470, y: 200)

  /// Writes `<out>.png` and `<out>@2x.png`; release.sh joins them into one TIFF for Finder.
  static func writeBackground(to out: String) -> Bool {
    [1, 2].allSatisfy { scale in
      guard let png = draw(scale: scale) else { return false }
      return (try? png.write(to: URL(fileURLWithPath: out + (scale == 2 ? "@2x.png" : ".png")))) != nil
    }
  }

  private static func draw(scale: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = size  // points, so 2x draws sharper rather than bigger
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
      NSColor(calibratedRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    func flip(_ y: CGFloat) -> CGFloat { size.height - y }  // AppKit counts from the bottom

    // Frosted glass, as on a guarded screen: a cool pale sheet with an amber glow where the app lands.
    NSGradient(starting: rgb(0xF5F6F9), ending: rgb(0xE3E7EE))?.draw(in: NSRect(origin: .zero, size: size), angle: 270)
    NSGradient(starting: rgb(0xF6B544, 0.16), ending: rgb(0xF6B544, 0))?
      .draw(fromCenter: NSPoint(x: applications.x, y: flip(applications.y)), radius: 0,
            toCenter: NSPoint(x: applications.x, y: flip(applications.y)), radius: 170, options: [])

    func text(_ s: String, size points: CGFloat, weight: NSFont.Weight, color: NSColor, top: CGFloat) {
      let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: points, weight: weight), .foregroundColor: color]
      let line = NSAttributedString(string: s, attributes: attributes)
      let width = line.size().width
      line.draw(at: NSPoint(x: (size.width - width) / 2, y: flip(top) - line.size().height))
    }
    text("Drag BRB into Applications", size: 19, weight: .semibold, color: rgb(0x1B2233), top: 46)
    text("把 BRB 拖进「应用程序」文件夹", size: 13, weight: .regular, color: rgb(0x5B6375), top: 76)

    // The arrow between the icons: amber, like the arm button.
    let start = app.x + 78, end = applications.x - 78, y = flip(app.y)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: start, y: y))
    arrow.line(to: NSPoint(x: end, y: y))
    arrow.move(to: NSPoint(x: end - 11, y: y + 10))
    arrow.line(to: NSPoint(x: end, y: y))
    arrow.line(to: NSPoint(x: end - 11, y: y - 10))
    arrow.lineWidth = 3.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    rgb(0xF0A53A).setStroke()
    arrow.stroke()

    text("Be right back.  Apple silicon · macOS 14 or later", size: 11, weight: .regular, color: rgb(0x8A91A0), top: 356)
    return rep.representation(using: .png, properties: [:])
  }
}
