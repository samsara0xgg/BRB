import AppKit
import SwiftUI

/// The shield of design A, in the 24 × 24 space of its SVG (y down). The same shape is the menu-bar
/// icon, the panel's tile and the notice's icon.
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

  /// The watch light: the round mark in the middle of a guarding shield.
  static let light = CGRect(x: 9.6, y: 9, width: 4.8, height: 4.8)
  /// The badge's red dot at the top right, and the gap cut around it.
  static let badge = CGRect(x: 16.5, y: 1.3, width: 6.2, height: 6.2)
  static let badgeGap = CGRect(x: 14.9, y: -0.3, width: 9.4, height: 9.4)

  static let amber = Theme.NS.amber
  static let red = Theme.NS.red
  static let green = Theme.NS.clear
}

/// The menu-bar icon, in eight looks (audit D3, D4):
/// idle: an outline that follows the menu bar's color. Arming: amber rising from the bottom.
/// Armed: amber with the watch light cut out, as on the notice. Partly guarded: half filled (H4).
/// Test: struck through (H1). Alarm: red with a mark. Clear: green with a tick, for 1.6 s after a
/// disarm. Badge: the outline with a red dot, until the panel shows the new alarm.
enum StatusIcon {
  enum Look: Equatable { case idle, arming(Double), armed, partial, test, alarm, clear, badge }

  /// `scale` grows or shrinks the shield about its middle, for the landing pop.
  static func image(_ look: Look, scale: CGFloat = 1) -> NSImage {
    let size: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
      guard let cg = NSGraphicsContext.current?.cgContext else { return false }
      cg.scaleBy(x: size / 24, y: size / 24)
      if scale != 1 {
        cg.translateBy(x: 12, y: 12)
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -12, y: -12)
      }
      draw(look, cg)
      return true
    }
    image.isTemplate = look == .idle
    image.accessibilityDescription = "BRB"
    return image
  }

  /// The landing pop over its 0.62 s: in from 40 %, over to 125 % (the most the 18-point image
  /// holds), back under to 94 %, settling at 100 %.
  static func pop(_ p: Double) -> CGFloat {
    let frames: [(Double, Double)] = [(0, 0.4), (0.45, 1.25), (0.72, 0.94), (1, 1)]
    guard p > 0 else { return 0.4 }
    guard p < 1 else { return 1 }
    for (a, b) in zip(frames, frames.dropFirst()) where p <= b.0 {
      return CGFloat(a.1 + (b.1 - a.1) * Ease.out((p - a.0) / (b.0 - a.0)))
    }
    return 1
  }

  private static func draw(_ look: Look, _ cg: CGContext) {
    let shield = Shield.outline()
    // Through NSColor so a system color resolves against the menu bar's own appearance.
    func stroke(_ color: NSColor, width: CGFloat = 1.9) {
      color.setStroke()
      cg.addPath(shield)
      cg.setLineWidth(width)
      cg.setLineJoin(.round)
      cg.strokePath()
    }
    func fill(_ path: CGPath, _ color: NSColor, evenOdd: Bool = false) {
      color.setFill()
      cg.addPath(path)
      cg.fillPath(using: evenOdd ? .evenOdd : .winding)
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
      let p = CGMutablePath()
      p.addPath(shield)
      p.addEllipse(in: Shield.light)
      fill(p, Shield.amber, evenOdd: true)
    case .partial:
      stroke(Shield.amber)
      fill(Shield.leftHalf(), Shield.amber)
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
      cg.move(to: CGPoint(x: 3.5, y: 20.5))
      cg.addLine(to: CGPoint(x: 20.5, y: 3.5))
      cg.setLineWidth(2.4)
      cg.setLineCap(.round)
      cg.strokePath()
    case .alarm:
      fill(shield, Shield.red)
      fill(Shield.mark(), .white)
    case .clear:
      fill(shield, Shield.green)
      NSColor.white.setStroke()
      cg.addPath(Shield.tick())
      cg.setLineWidth(2.2)
      cg.setLineCap(.round)
      cg.setLineJoin(.round)
      cg.strokePath()
    case .badge:
      cg.saveGState()
      let around = CGMutablePath()
      around.addRect(CGRect(x: -2, y: -2, width: 28, height: 28))
      around.addEllipse(in: Shield.badgeGap)
      cg.addPath(around)
      cg.clip(using: .evenOdd)
      stroke(.labelColor)
      cg.restoreGState()
      fill(CGPath(ellipseIn: Shield.badge, transform: nil), Shield.red)
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

/// The tick alone, so it can draw itself in.
struct TickShape: Shape {
  func path(in rect: CGRect) -> Path { Path(Shield.tick(ShieldShape.fit(rect))) }
}

/// The shield glyph on the panel's tile, the start button and the notice. The panel's tile follows
/// the menu bar (audit A4): an outline while idle, amber rising while counting down, amber with the
/// watch light while guarding, red on an alarm, green with a tick once disarmed. `ink` is the start
/// button's: the shield cut out of the amber.
struct ShieldGlyph: View {
  enum Look: Equatable { case outline, arming(Double), guarding, alarm, clear, ink }
  let look: Look
  var line = Color.white.opacity(0.92)
  /// The welcome tick draws itself in.
  var drawsTick = false
  @State private var drawn: CGFloat = 0

  var body: some View {
    Canvas { ctx, size in
      let t = ShieldShape.fit(CGRect(origin: .zero, size: size))
      let shield = Path(Shield.outline(t))
      let edge = StrokeStyle(lineWidth: 1.9 * t.a, lineJoin: .round)
      switch look {
      case .outline:
        ctx.stroke(shield, with: .color(line), style: edge)
      case .arming(let level):
        ctx.stroke(shield, with: .color(Theme.amber), style: edge)
        let top = 21.5 - 18.7 * min(max(level, 0), 1)
        var inside = ctx
        inside.clip(to: Path(CGRect(x: 0, y: top, width: 24, height: 24 - top).applying(t)))
        inside.fill(shield, with: .color(Theme.amber))
      case .guarding:
        ctx.fill(shield, with: .color(Theme.amber))
        ctx.fill(Path(ellipseIn: Shield.light.applying(t)), with: .color(Theme.ink))
      case .ink:
        ctx.fill(shield, with: .color(Theme.ink))
        ctx.fill(Path(ellipseIn: Shield.light.applying(t)), with: .color(Theme.amberHi))
      case .alarm:
        ctx.fill(shield, with: .color(Theme.red))
        ctx.fill(Path(Shield.mark(t)), with: .color(.white))
      case .clear:
        ctx.fill(shield, with: .color(Theme.green))
        if !drawsTick {
          ctx.stroke(Path(Shield.tick(t)), with: .color(.white), style: StrokeStyle(lineWidth: 2.1 * t.a, lineCap: .round, lineJoin: .round))
        }
      }
    }
    .overlay {
      if drawsTick && look == .clear {
        GeometryReader { g in
          TickShape()
            .trim(from: 0, to: drawn)
            .stroke(.white, style: StrokeStyle(lineWidth: 2.1 * min(g.size.width, g.size.height) / 24, lineCap: .round, lineJoin: .round))
        }
      }
    }
    .onAppear {
      guard drawsTick else { return }
      withAnimation(Theme.out(0.5).delay(0.25)) { drawn = 1 }
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
  static let retreat = Ease(0.4, 0, 0.2, 1)      // the fog pulling back on a cancel, the ring unwinding
  static let melt = Ease(0.3, 0.15, 0.25, 1)     // the fog clearing on the way back, 1.4 s
  static let out = Ease(0.22, 0.9, 0.3, 1)       // Theme.out: quick out, long settle
}
