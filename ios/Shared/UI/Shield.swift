import SwiftUI

/// The eight looks of the shield, the same as in the Mac menu bar.
enum ShieldLook: Equatable {
  case idle, arming, armed, partial, test, alarm, warn, clear, offline
}

extension Look {
  var shield: ShieldLook {
    switch self {
    case .idle: return .idle
    case .arming: return .arming
    case .armed: return .armed
    case .partial: return .partial
    case .test: return .test
    case .warn: return .warn
    case .alarm: return .alarm
    case .offline: return .offline
    }
  }
}

/// The shield outline and its left half, in the prototype's 24 by 24 box.
enum ShieldGeometry {
  static func outline() -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 12, y: 2.8))
    p.addLine(to: CGPoint(x: 19.4, y: 5.6))
    p.addLine(to: CGPoint(x: 19.4, y: 11.4))
    p.addCurve(to: CGPoint(x: 12, y: 21.5), control1: CGPoint(x: 19.4, y: 16.2), control2: CGPoint(x: 16.3, y: 20))
    p.addCurve(to: CGPoint(x: 4.6, y: 11.4), control1: CGPoint(x: 7.7, y: 20), control2: CGPoint(x: 4.6, y: 16.2))
    p.addLine(to: CGPoint(x: 4.6, y: 5.6))
    p.closeSubpath()
    return p
  }

  static func leftHalf() -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 12, y: 2.8))
    p.addLine(to: CGPoint(x: 12, y: 21.5))
    p.addCurve(to: CGPoint(x: 4.6, y: 11.4), control1: CGPoint(x: 7.7, y: 20), control2: CGPoint(x: 4.6, y: 16.2))
    p.addLine(to: CGPoint(x: 4.6, y: 5.6))
    p.closeSubpath()
    return p
  }
}

/// The BRB shield. `mono` draws it in the surrounding foreground color only (widgets, lock screen,
/// Dynamic Island). `progress` is how far the fill has risen while arming.
struct ShieldView: View {
  var look: ShieldLook
  var size: CGFloat = 58
  var mono = false
  var progress: Double = 0.5

  var body: some View {
    Canvas { ctx, canvasSize in
      let k = min(canvasSize.width, canvasSize.height) / 24
      var c = ctx
      c.translateBy(x: (canvasSize.width - 24 * k) / 2, y: (canvasSize.height - 24 * k) / 2)
      c.scaleBy(x: k, y: k)
      draw(&c)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var amber: GraphicsContext.Shading { mono ? .foreground : .color(Theme.amber) }
  private var amberStroke: GraphicsContext.Shading { mono ? .foreground : .color(Theme.amber) }
  private var ink: GraphicsContext.Shading { mono ? .color(.black.opacity(0.8)) : .color(Theme.amberInk) }

  private func draw(_ c: inout GraphicsContext) {
    let outline = ShieldGeometry.outline()
    let round = StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
    switch look {
    case .idle:
      c.stroke(outline, with: .foreground, style: StrokeStyle(lineWidth: 1.7, lineJoin: .round))

    case .arming:
      c.stroke(outline, with: amberStroke, style: round)
      var inner = c
      let top = 21.5 - (21.5 - 2.8) * max(0, min(1, progress))
      inner.clip(to: Path(CGRect(x: 0, y: top, width: 24, height: 24)))
      inner.fill(outline, with: amber)

    case .armed:
      c.fill(outline, with: amber)
      if mono {
        var hole = c
        hole.blendMode = .destinationOut
        hole.fill(Path(ellipseIn: CGRect(x: 9.6, y: 9, width: 4.8, height: 4.8)), with: .color(.black))
      } else {
        c.fill(Path(ellipseIn: CGRect(x: 9.6, y: 9, width: 4.8, height: 4.8)), with: ink)
      }

    case .partial:
      c.stroke(outline, with: amberStroke, style: round)
      c.fill(ShieldGeometry.leftHalf(), with: amber)

    case .test:
      var layer = c
      layer.drawLayer { l in
        l.fill(outline, with: amber)
        var band = l
        band.blendMode = .destinationOut
        var slash = Path()
        slash.move(to: CGPoint(x: 2.84, y: 24.84))
        slash.addLine(to: CGPoint(x: 24.84, y: 2.84))
        slash.addLine(to: CGPoint(x: 21.16, y: -0.84))
        slash.addLine(to: CGPoint(x: -0.84, y: 21.16))
        slash.closeSubpath()
        band.fill(slash, with: .color(.black))
      }
      var line = Path()
      line.move(to: CGPoint(x: 3.5, y: 20.5))
      line.addLine(to: CGPoint(x: 20.5, y: 3.5))
      c.stroke(line, with: .foreground, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

    case .alarm, .warn:
      let fill: GraphicsContext.Shading = mono ? .foreground : .color(look == .alarm ? Theme.red : Theme.orange)
      c.fill(outline, with: fill)
      let bar = Path(roundedRect: CGRect(x: 11, y: 6.6, width: 2, height: 7.4), cornerRadius: 1)
      let dot = Path(ellipseIn: CGRect(x: 10.75, y: 15.65, width: 2.5, height: 2.5))
      if mono {
        var hole = c
        hole.blendMode = .destinationOut
        hole.fill(bar, with: .color(.black))
        hole.fill(dot, with: .color(.black))
      } else {
        c.fill(bar, with: .color(.white))
        c.fill(dot, with: .color(.white))
      }

    case .clear:
      c.fill(outline, with: mono ? .foreground : .color(Theme.green))
      var tick = Path()
      tick.move(to: CGPoint(x: 8.4, y: 11.8))
      tick.addLine(to: CGPoint(x: 10.9, y: 14.3))
      tick.addLine(to: CGPoint(x: 15.7, y: 9.3))
      let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
      if mono {
        var hole = c
        hole.blendMode = .destinationOut
        hole.stroke(tick, with: .color(.black), style: style)
      } else {
        c.stroke(tick, with: .color(.white), style: style)
      }

    case .offline:
      c.stroke(
        outline, with: mono ? .color(.primary.opacity(0.6)) : .color(Theme.gray),
        style: StrokeStyle(lineWidth: 1.7, lineJoin: .round, dash: [2.6, 2.2]))
    }
  }
}

#Preview {
  let looks: [ShieldLook] = [.idle, .arming, .armed, .partial, .test, .alarm, .warn, .clear, .offline]
  return LazyVGrid(columns: Array(repeating: GridItem(.fixed(70)), count: 5), spacing: 16) {
    ForEach(Array(looks.enumerated()), id: \.offset) { _, l in ShieldView(look: l, size: 58) }
  }
  .padding()
  .background(Theme.bg)
  .foregroundStyle(Theme.ink)
}
