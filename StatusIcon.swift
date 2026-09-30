import AppKit
import SwiftUI

/// The shield of design A, in the 24 × 24 space of its SVG (y down). The same shape is the menu-bar
/// icon, the panel's logo and the notice's icon.
enum Shield {
  static func outline(_ t: CGAffineTransform = .identity) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 12, y: 2.8), transform: t)
    p.addLine(to: CGPoint(x: 19.4, y: 5.6), transform: t)
    p.addLine(to: CGPoint(x: 19.4, y: 11.4), transform: t)
    p.addCurve(to: CGPoint(x: 12, y: 21.5), control1: CGPoint(x: 19.4, y: 16.2), control2: CGPoint(x: 16.3, y: 20), transform: t)
    p.addCurve(to: CGPoint(x: 4.6, y: 11.4), control1: CGPoint(x: 7.7, y: 20), control2: CGPoint(x: 4.6, y: 16.2), transform: t)
    p.addLine(to: CGPoint(x: 4.6, y: 5.6), transform: t)
    p.closeSubpath()
    return p
  }

  /// The left half, for "partly guarded".
  static func leftHalf(_ t: CGAffineTransform = .identity) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 12, y: 2.8), transform: t)
    p.addLine(to: CGPoint(x: 12, y: 21.5), transform: t)
    p.addCurve(to: CGPoint(x: 4.6, y: 11.4), control1: CGPoint(x: 7.7, y: 20), control2: CGPoint(x: 4.6, y: 16.2), transform: t)
    p.addLine(to: CGPoint(x: 4.6, y: 5.6), transform: t)
    p.closeSubpath()
    return p
  }

  /// The alarm's exclamation mark.
  static func mark(_ t: CGAffineTransform = .identity) -> CGPath {
    let p = CGMutablePath()
    p.addRoundedRect(in: CGRect(x: 11, y: 6.6, width: 2, height: 7.4), cornerWidth: 1, cornerHeight: 1, transform: t)
    p.addEllipse(in: CGRect(x: 10.75, y: 15.65, width: 2.5, height: 2.5), transform: t)
    return p
  }

  /// The welcome-back tick.
  static func tick(_ t: CGAffineTransform = .identity) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 8.4, y: 11.8), transform: t)
    p.addLine(to: CGPoint(x: 10.9, y: 14.3), transform: t)
    p.addLine(to: CGPoint(x: 15.7, y: 9.3), transform: t)
    return p
  }

  static let amber = NSColor(srgbRed: 0xF6 / 255.0, green: 0xB5 / 255.0, blue: 0x44 / 255.0, alpha: 1)
  static let red = NSColor(srgbRed: 1, green: 0x4D / 255.0, blue: 0x55 / 255.0, alpha: 1)
  static let dot = NSColor(srgbRed: 0x2B / 255.0, green: 0x1A / 255.0, blue: 0, alpha: 1)
}

/// The menu-bar icon. Off: an outline template image that follows the menu bar's color. Counting
/// down: amber rising from the bottom. Armed: amber. Alarm: red with a mark. Test mode: struck
/// through (audit H1). Partly guarded: half filled (audit H4).
enum StatusIcon {
  enum Look: Equatable { case idle, arming(Double), armed, alarm, test, partial }

  static func image(_ look: Look) -> NSImage {
    let size: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
      guard let cg = NSGraphicsContext.current?.cgContext else { return false }
      cg.scaleBy(x: size / 24, y: size / 24)
      draw(look, cg)
      return true
    }
    image.isTemplate = look == .idle
    image.accessibilityDescription = "Guard Mode"
    return image
  }

  private static func draw(_ look: Look, _ cg: CGContext) {
    let shield = Shield.outline()
    func stroke(_ color: NSColor) {
      cg.addPath(shield)
      cg.setStrokeColor(color.cgColor)
      cg.setLineWidth(1.9)
      cg.setLineJoin(.round)
      cg.strokePath()
    }
    func fill(_ path: CGPath, _ color: NSColor) {
      cg.addPath(path)
      cg.setFillColor(color.cgColor)
      cg.fillPath()
    }
    switch look {
    case .idle:
      stroke(.black)
    case .arming(let level):
      stroke(Shield.amber)
      cg.saveGState()
      let top = 21.5 - 18.7 * CGFloat(min(max(level, 0), 1))
      cg.clip(to: CGRect(x: 0, y: top, width: 24, height: 24 - top))
      fill(shield, Shield.amber)
      cg.restoreGState()
    case .armed:
      fill(shield, Shield.amber)
    case .alarm:
      fill(shield, Shield.red)
      fill(Shield.mark(), .white)
    case .test:
      // Amber with a gap along the diagonal, and the slash in the menu bar's own text color.
      cg.saveGState()
      let n: CGFloat = 1.84  // half of the 5.2 pt gap, along both axes
      let band = CGMutablePath()
      band.addLines(between: [CGPoint(x: 1 + n, y: 23 + n), CGPoint(x: 23 + n, y: 1 + n), CGPoint(x: 23 - n, y: 1 - n), CGPoint(x: 1 - n, y: 23 - n)])
      band.closeSubpath()
      let outside = CGMutablePath()
      outside.addRect(CGRect(x: -2, y: -2, width: 28, height: 28))
      outside.addPath(band)
      cg.addPath(outside)
      cg.clip(using: .evenOdd)
      fill(shield, Shield.amber)
      cg.restoreGState()
      NSColor.labelColor.setStroke()
      let slash = NSBezierPath()
      slash.move(to: NSPoint(x: 3.5, y: 20.5))
      slash.line(to: NSPoint(x: 20.5, y: 3.5))
      slash.lineWidth = 2.4
      slash.lineCapStyle = .round
      slash.stroke()
    case .partial:
      stroke(Shield.amber)
      fill(Shield.leftHalf(), Shield.amber)
    }
  }
}

/// The shield for SwiftUI, scaled into its frame.
struct ShieldShape: Shape {
  var half = false

  func path(in rect: CGRect) -> Path {
    Path(half ? Shield.leftHalf(ShieldShape.fit(rect)) : Shield.outline(ShieldShape.fit(rect)))
  }

  static func fit(_ rect: CGRect) -> CGAffineTransform {
    let s = min(rect.width, rect.height) / 24
    return CGAffineTransform(translationX: rect.midX - 12 * s, y: rect.midY - 12 * s).scaledBy(x: s, y: s)
  }
}

/// The shield glyph in its three looks: guarding (amber with the watch light), alarm, all clear.
struct ShieldGlyph: View {
  enum Look { case guarding, alarm, clear, outline }
  let look: Look

  var body: some View {
    Canvas { ctx, size in
      let t = ShieldShape.fit(CGRect(origin: .zero, size: size))
      let shield = Path(Shield.outline(t))
      switch look {
      case .guarding:
        ctx.fill(shield, with: .color(Color(nsColor: Shield.amber)))
        let d = Path(ellipseIn: CGRect(x: 9.6, y: 9, width: 4.8, height: 4.8).applying(t))
        ctx.fill(d, with: .color(Color(nsColor: Shield.dot)))
      case .alarm:
        ctx.fill(shield, with: .color(Color(red: 1, green: 0x5A / 255, blue: 0x61 / 255)))
        ctx.fill(Path(Shield.mark(t)), with: .color(.white))
      case .clear:
        ctx.fill(shield, with: .color(Color(red: 0x46 / 255, green: 0xD4 / 255, blue: 0x83 / 255)))
        ctx.stroke(Path(Shield.tick(t)), with: .color(.white), style: StrokeStyle(lineWidth: 2 * t.a, lineCap: .round, lineJoin: .round))
      case .outline:
        ctx.stroke(shield, with: .color(Color(nsColor: Shield.amber)), style: StrokeStyle(lineWidth: 1.9 * t.a, lineJoin: .round))
      }
    }
  }
}

/// A CSS-style cubic-bezier timing curve, for the numbers in design A's motion table.
struct Ease {
  let x1, y1, x2, y2: Double

  init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
    self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
  }

  func callAsFunction(_ t: Double) -> Double {
    guard t > 0 else { return 0 }
    guard t < 1 else { return 1 }
    var lo = 0.0, hi = 1.0, s = t
    for _ in 0..<24 {  // x(s) rises monotonically for x1, x2 in 0...1: bisect for x(s) = t
      s = (lo + hi) / 2
      if Ease.bezier(s, x1, x2) < t { lo = s } else { hi = s }
    }
    return Ease.bezier(s, y1, y2)
  }

  private static func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
    3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s
  }

  static let fog = Ease(0.2, 0.6, 0.35, 1)       // the fog spreading while counting down, 5 s
  static let retreat = Ease(0.4, 0, 0.2, 1)      // the fog pulling back on a cancel
  static let melt = Ease(0.3, 0.15, 0.25, 1)     // the fog clearing on the way back, 1.4 s
}
