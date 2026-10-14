import AppKit
import SwiftUI

/// Design A's tokens, the same values as the iPhone app: one amber, one red, one green, four type
/// sizes for the panel and one set of motion curves. Every view takes its colors and timing from
/// here (audit D1, D2).
enum Theme {
  static let amber = Color(nsColor: NS.amber)
  static let amberHi = Color(nsColor: NS.amberHi)
  static let amberDeep = Color(nsColor: NS.amberDeep)
  /// Text and marks on amber.
  static let ink = Color(nsColor: NS.ink)
  static let stripe = Color(nsColor: NS.stripe)
  static let red = Color(nsColor: NS.red)
  static let redDeep = Color(nsColor: NS.redDeep)
  static let flood = Color(nsColor: NS.flood)
  /// Ready and disarmed: #46D483, darker on a light background so it still reads.
  static let green = Color(nsColor: NS.green)
  static let greenText = Color(nsColor: NS.greenText)
  /// Alarms in lists: light amber on dark, dark amber on light.
  static let warn = Color(nsColor: NS.warn)
  /// The camera light's green, for "walking by isn't recorded".
  static let camera = Color(nsColor: NS.camera)
  static let tile = LinearGradient(colors: [Color(nsColor: NS.rgb(0x2B3A6B)), Color(nsColor: NS.rgb(0x131A33))],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)

  /// Wells and quiet buttons on the panel, in either appearance.
  static let fill = Color.primary.opacity(0.06)
  static let fill2 = Color.primary.opacity(0.1)
  static let separator = Color.primary.opacity(0.1)
  /// The knob of the place picker.
  static let knob = Color(nsColor: NS.dynamic(dark: NSColor(white: 1, alpha: 0.22), light: .white))
  static let knobText = Color(nsColor: NS.dynamic(dark: .white, light: NS.rgb(0x121826)))

  // The panel's four sizes.
  static let title = Font.system(size: 15, weight: .semibold)
  static let body = Font.system(size: 13)
  static let caption = Font.system(size: 12)
  static let label = Font.system(size: 11)

  /// The glass stretching from the ring into the notice.
  static let glass = Animation.spring(duration: 0.62, bounce: 0.3)
  /// Knobs and cards sliding into place.
  static let slide = Animation.spring(duration: 0.42, bounce: 0.22)
  /// The panel and its cards growing or shrinking.
  static let resize = Animation.spring(duration: 0.38, bounce: 0.1)

  /// Quick out, long settle: most of the panel's fades and moves.
  static func out(_ seconds: Double) -> Animation { .timingCurve(0.22, 0.9, 0.3, 1, duration: seconds) }

  /// With Reduce Motion every move becomes a 200 ms fade.
  static func motion(_ animation: Animation, reduced: Bool) -> Animation { reduced ? .easeInOut(duration: 0.2) : animation }

  enum NS {
    static let amber = rgb(0xF6B544)
    static let amberHi = rgb(0xFFCF6E)
    static let amberDeep = rgb(0xF0A53A)
    static let ink = rgb(0x2B1A00)
    static let stripe = rgb(0xF6BE5E)
    static let red = rgb(0xFF4D55)
    static let redDeep = rgb(0xC41828)
    static let flood = rgb(0xDC2634)
    static let green = dynamic(dark: rgb(0x46D483), light: rgb(0x2FBF6E))
    static let greenText = dynamic(dark: rgb(0x5BE39A), light: rgb(0x14894A))
    static let warn = dynamic(dark: rgb(0xFFC261), light: rgb(0xB86B00))
    static let camera = rgb(0x3EF07A)
    /// The menu-bar shield's green: the bar is light or dark, never the panel's background.
    static let clear = rgb(0x46D483)

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
      NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
      NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
  }
}

/// 45° bands, as CSS's repeating-linear-gradient(135deg): what marks a silent run everywhere (the
/// test-mode switch, the start button, the notice's tag). `offset` moves them along, for marching.
struct Stripes: View {
  var band: CGFloat = 6
  var color = Theme.stripe
  var offset: CGFloat = 0

  var body: some View {
    Canvas { ctx, size in
      let step = band * 2 * CGFloat(2).squareRoot()
      var p = Path()
      var x = -size.height - step + offset.truncatingRemainder(dividingBy: step)
      while x < size.width + size.height {
        p.move(to: CGPoint(x: x, y: size.height))
        p.addLine(to: CGPoint(x: x + size.height, y: 0))
        x += step
      }
      ctx.stroke(p, with: .color(color), lineWidth: band)
    }
    .allowsHitTesting(false)
  }
}

/// A sideways shake that settles: "not yet" without a dialog. Each increment of `count` plays it once.
struct Shake: GeometryEffect {
  var amount: CGFloat
  var animatableData: CGFloat

  init(_ count: Int, amount: CGFloat = 8) {
    self.amount = amount
    animatableData = CGFloat(count)
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    let f = animatableData - floor(animatableData)
    return ProjectionTransform(CGAffineTransform(translationX: amount * sin(f * .pi * 4) * (1 - f), y: 0))
  }
}

/// The midnight tile behind the shield: the app icon's ground.
struct Tile: View {
  let look: ShieldGlyph.Look
  var size: CGFloat = 28

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).fill(Theme.tile)
      RoundedRectangle(cornerRadius: size * 0.29, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
      ShieldGlyph(look: look).frame(width: size * 0.62, height: size * 0.62)
    }
    .frame(width: size, height: size)
    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
  }
}

/// A key as printed on the keyboard: "esc", "↩", the Touch ID key. `dark`: the frosted screen's,
/// larger and white.
struct Keycap<Label: View>: View {
  var dark = false
  @ViewBuilder let label: Label

  var body: some View {
    label
      .foregroundStyle(dark ? AnyShapeStyle(Color.white) : AnyShapeStyle(HierarchicalShapeStyle.primary))
      .padding(.horizontal, dark ? 7 : 6)
      .frame(minWidth: dark ? 32 : 24, minHeight: dark ? 26 : 22)
      .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(dark ? Color.white.opacity(0.16) : Theme.ink.opacity(0.1)))
      .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(dark ? Color.white.opacity(0.32) : Theme.ink.opacity(0.16), lineWidth: 0.5))
      .shadow(color: .black.opacity(dark ? 0.25 : 0), radius: 0, y: 1)
  }
}

/// Opacity, a few points of travel and a little blur: how words swap in place.
struct Blurred: ViewModifier {
  let radius: CGFloat
  func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
  static func words(_ travel: CGFloat = 6) -> AnyTransition {
    AnyTransition.modifier(active: Blurred(radius: 3), identity: Blurred(radius: 0))
      .combined(with: .opacity)
      .combined(with: .offset(y: travel))
  }
}
