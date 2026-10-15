import SwiftUI

#if canImport(UIKit) && !os(watchOS)
  import UIKit
#endif

/// 0xRRGGBB plus an alpha.
struct RGBA {
  var hex: UInt32
  var a: Double = 1
  var color: Color {
    Color(
      .sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255,
      opacity: a)
  }
  #if canImport(UIKit) && !os(watchOS)
    var ui: UIColor {
      UIColor(
        red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255,
        alpha: a)
    }
  #endif
}

extension Color {
  /// A color that follows the light and dark appearance. The Watch is always dark.
  static func dyn(dark: RGBA, light: RGBA) -> Color {
    #if canImport(UIKit) && !os(watchOS)
      return Color(UIColor { $0.userInterfaceStyle == .dark ? dark.ui : light.ui })
    #else
      return dark.color
    #endif
  }
  static func dyn(_ dark: UInt32, _ light: UInt32) -> Color { dyn(dark: RGBA(hex: dark), light: RGBA(hex: light)) }
}

/// The colors of the phone prototype, in light and dark. Shared with the Mac redesign: amber, red, flood
/// red, green and the camera green are the same values there.
enum Theme {
  // Surfaces
  static let bg = Color.dyn(0x0b0f1c, 0xf2f3f8)
  static let bgTop = Color.dyn(0x1b2440, 0xe1e7f5)
  static let sheet = Color.dyn(0x121929, 0xf7f8fb)
  static let card = Color.dyn(dark: RGBA(hex: 0xffffff, a: 0.055), light: RGBA(hex: 0xffffff))
  static let cardBorder = Color.dyn(dark: RGBA(hex: 0xffffff, a: 0.08), light: RGBA(hex: 0xffffff, a: 0))
  static let cardHi = Color.dyn(dark: RGBA(hex: 0xffffff, a: 0.10), light: RGBA(hex: 0x0e1324, a: 0.055))
  static let field = Color.dyn(dark: RGBA(hex: 0xffffff, a: 0.07), light: RGBA(hex: 0x0e1324, a: 0.055))
  static let skeleton = Color.dyn(dark: RGBA(hex: 0xffffff, a: 0.07), light: RGBA(hex: 0x0e1324, a: 0.06))
  static let skeleton2 = Color.dyn(dark: RGBA(hex: 0xffffff, a: 0.13), light: RGBA(hex: 0x0e1324, a: 0.11))
  static let hair = Color.dyn(dark: RGBA(hex: 0xffffff, a: 0.08), light: RGBA(hex: 0x0e1324, a: 0.08))
  static let rim = Color.dyn(dark: RGBA(hex: 0xffffff, a: 0.13), light: RGBA(hex: 0x0e1324, a: 0.10))

  // Text
  static let ink = Color.dyn(0xeef1f8, 0x0e1324)
  static let ink2 = Color.dyn(dark: RGBA(hex: 0xeef1f8, a: 0.64), light: RGBA(hex: 0x0e1324, a: 0.60))
  static let ink3 = Color.dyn(dark: RGBA(hex: 0xeef1f8, a: 0.40), light: RGBA(hex: 0x0e1324, a: 0.38))

  // Accents
  static let tint = Color.dyn(0x8aa8ff, 0x3a5bd9)
  static let tintBg = Color.dyn(dark: RGBA(hex: 0x8aa8ff, a: 0.16), light: RGBA(hex: 0x3a5bd9, a: 0.10))

  // Shield fills (shapes) and their text-safe twins
  static let amber = Color(hex: 0xf6b544)
  static let amberHi = Color(hex: 0xffcf6e)
  static let amberDeep = Color(hex: 0xf0a53a)
  static let amberInk = Color(hex: 0x2b1a00)
  static let orange = Color(hex: 0xff8a3d)
  static let red = Color.dyn(0xff4d55, 0xef3b47)
  static let flood = Color(hex: 0xdc2634)
  static let green = Color.dyn(0x46d483, 0x2fbf6e)
  static let cameraGreen = Color(hex: 0x3ef07a)
  static let gray = Color.dyn(0x8f96ab, 0x9aa0b2)

  static let textAmber = Color.dyn(0xf6b544, 0xa86f00)
  static let textOrange = Color.dyn(0xff9d5c, 0xc9570c)
  static let textRed = Color.dyn(0xff7a80, 0xd7263a)
  static let textGreen = Color.dyn(0x5be39a, 0x14894a)
  static let textGray = Color.dyn(0x9aa1b5, 0x6d7385)

  static let yellowBg = Color.dyn(dark: RGBA(hex: 0xffd60a, a: 0.13), light: RGBA(hex: 0xfff1b8))
  static let yellowInk = Color.dyn(0xffd60a, 0x6b4e00)

  /// The headline color for a look: amber while guarding, red in an alarm...
  static func text(for look: Look) -> Color {
    switch look {
    case .arming, .armed, .partial: return textAmber
    case .alarm: return textRed
    case .warn: return textOrange
    case .offline: return textGray
    case .idle, .test: return ink
    }
  }
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255,
      opacity: opacity)
  }
}

/// The soft gradient behind every screen.
struct Backdrop: View {
  var body: some View {
    ZStack {
      Theme.bg
      RadialGradient(colors: [Theme.bgTop, Theme.bg.opacity(0)], center: .init(x: 0.5, y: 0), startRadius: 0, endRadius: 420)
        .scaleEffect(x: 1.2, y: 0.46, anchor: .top)
    }
    .ignoresSafeArea()
  }
}

extension Font {
  /// SF Pro Rounded, for numbers and countdowns.
  static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
    .system(size: size, weight: weight, design: .rounded)
  }
}
