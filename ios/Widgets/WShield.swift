import SwiftUI

/// A path drawn in the shield's 24 by 24 box, scaled to whatever square it is given.
struct WBoxShape: Shape {
  var box: Path

  func path(in rect: CGRect) -> Path {
    let k = min(rect.width, rect.height) / 24
    let tx = rect.minX + (rect.width - 24 * k) / 2
    let ty = rect.minY + (rect.height - 24 * k) / 2
    return box.applying(CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: tx, ty: ty))
  }
}

/// The parts of the shield, in its 24 by 24 box (same numbers as ShieldView, Shield.swift).
enum WShieldArt {
  static var outline: Path { ShieldGeometry.outline() }
  static var leftHalf: Path { ShieldGeometry.leftHalf() }

  /// The shield with the dot of "guarding" cut out (draw with the even-odd rule).
  static var armedHole: Path {
    var p = ShieldGeometry.outline()
    p.addEllipse(in: CGRect(x: 9.6, y: 9, width: 4.8, height: 4.8))
    return p
  }
  static var dot: Path { Path(ellipseIn: CGRect(x: 9.6, y: 9, width: 4.8, height: 4.8)) }

  /// The shield with the "!" cut out.
  static var alertHole: Path {
    var p = ShieldGeometry.outline()
    p.addRoundedRect(in: CGRect(x: 11, y: 6.6, width: 2, height: 7.4), cornerSize: CGSize(width: 1, height: 1))
    p.addEllipse(in: CGRect(x: 10.75, y: 15.65, width: 2.5, height: 2.5))
    return p
  }
  static var alertMark: Path {
    var p = Path()
    p.addRoundedRect(in: CGRect(x: 11, y: 6.6, width: 2, height: 7.4), cornerSize: CGSize(width: 1, height: 1))
    p.addEllipse(in: CGRect(x: 10.75, y: 15.65, width: 2.5, height: 2.5))
    return p
  }

  static var tick: Path {
    var p = Path()
    p.move(to: CGPoint(x: 8.4, y: 11.8))
    p.addLine(to: CGPoint(x: 10.9, y: 14.3))
    p.addLine(to: CGPoint(x: 15.7, y: 9.3))
    return p
  }

  /// The slash through the test shield.
  static var slash: Path {
    var p = Path()
    p.move(to: CGPoint(x: 3.5, y: 20.5))
    p.addLine(to: CGPoint(x: 20.5, y: 3.5))
    return p
  }

  /// Everything but the diagonal band that the test shield cuts out (draw with the even-odd rule).
  static var bandCut: Path {
    var p = Path(CGRect(x: 0, y: 0, width: 24, height: 24))
    p.move(to: CGPoint(x: 2.84, y: 24.84))
    p.addLine(to: CGPoint(x: 24.84, y: 2.84))
    p.addLine(to: CGPoint(x: 21.16, y: -0.84))
    p.addLine(to: CGPoint(x: -0.84, y: 21.16))
    p.closeSubpath()
    return p
  }
}

/// The BRB shield for widgets and activities. The same eight looks as ShieldView, drawn with shapes instead of
/// a Canvas (a widget is drawn from a snapshot of its view tree, and shapes are what that handles for sure).
/// `mono` uses the primary color only, for the Lock Screen and the Dynamic Island.
struct WShield: View {
  var look: ShieldLook
  var size: CGFloat = 40
  var mono = false
  /// How far the fill has risen while arming, 0 to 1.
  var progress: Double = 0.5

  private var k: CGFloat { size / 24 }
  private var amber: Color { mono ? Color.primary : Theme.amber }

  var body: some View {
    ZStack { art }
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }

  private func roundStroke(_ width: CGFloat) -> StrokeStyle {
    StrokeStyle(lineWidth: width * k, lineCap: .round, lineJoin: .round)
  }

  @ViewBuilder private var art: some View {
    switch look {
    case .idle:
      WBoxShape(box: WShieldArt.outline)
        .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.7 * k, lineJoin: .round))

    case .arming:
      let p = max(0, min(1, progress))
      let risen = (2.5 + 18.7 * p) * Double(k)
      WBoxShape(box: WShieldArt.outline).stroke(amber, style: roundStroke(1.9))
      WBoxShape(box: WShieldArt.outline)
        .fill(amber)
        .mask(alignment: .bottom) { Rectangle().frame(height: CGFloat(risen)) }

    case .armed:
      if mono {
        WBoxShape(box: WShieldArt.armedHole).fill(amber, style: FillStyle(eoFill: true))
      } else {
        WBoxShape(box: WShieldArt.outline).fill(amber)
        WBoxShape(box: WShieldArt.dot).fill(Theme.amberInk)
      }

    case .partial:
      WBoxShape(box: WShieldArt.outline).stroke(amber, style: roundStroke(1.9))
      WBoxShape(box: WShieldArt.leftHalf).fill(amber)

    case .test:
      WBoxShape(box: WShieldArt.outline)
        .fill(amber)
        .mask { WBoxShape(box: WShieldArt.bandCut).fill(Color.black, style: FillStyle(eoFill: true)) }
      WBoxShape(box: WShieldArt.slash)
        .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round))

    case .alarm, .warn:
      let fill: Color = mono ? Color.primary : (look == .alarm ? Theme.red : Theme.orange)
      if mono {
        WBoxShape(box: WShieldArt.alertHole).fill(fill, style: FillStyle(eoFill: true))
      } else {
        WBoxShape(box: WShieldArt.outline).fill(fill)
        WBoxShape(box: WShieldArt.alertMark).fill(Color.white)
      }

    case .clear:
      WBoxShape(box: WShieldArt.outline).fill(mono ? Color.primary : Theme.green)
      WBoxShape(box: WShieldArt.tick).stroke(mono ? Color.black.opacity(0.75) : Color.white, style: roundStroke(2))

    case .offline:
      WBoxShape(box: WShieldArt.outline)
        .stroke(
          mono ? Color.primary.opacity(0.6) : Theme.gray,
          style: StrokeStyle(lineWidth: 1.7 * k, lineJoin: .round, dash: [2.6 * k, 2.2 * k]))
    }
  }
}
