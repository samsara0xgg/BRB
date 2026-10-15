import SwiftUI

/// A full-width pill, the way the prototype draws the Watch's buttons. At least 44 pt tall.
struct WPillStyle: ButtonStyle {
  var fill: AnyShapeStyle
  var ink: Color = Color.white
  var height: CGFloat = 44

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 15, weight: .bold))
      .foregroundStyle(ink)
      .frame(maxWidth: .infinity, minHeight: height)
      .background(Capsule().fill(fill))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

extension WPillStyle {
  static var amber: WPillStyle {
    let gradient = LinearGradient(colors: [Theme.amberHi, Theme.amberDeep], startPoint: .top, endPoint: .bottom)
    return WPillStyle(fill: AnyShapeStyle(gradient), ink: Theme.amberInk)
  }
  static var red: WPillStyle { WPillStyle(fill: AnyShapeStyle(Theme.red), ink: Color.white) }
  static var orange: WPillStyle { WPillStyle(fill: AnyShapeStyle(Theme.orange), ink: Color.white) }
  static var white: WPillStyle { WPillStyle(fill: AnyShapeStyle(Color.white), ink: Color.black) }
  static var gray: WPillStyle { WPillStyle(fill: AnyShapeStyle(Color(white: 1, opacity: 0.16)), ink: Color.white) }
  static var dim: WPillStyle { WPillStyle(fill: AnyShapeStyle(Color(white: 1, opacity: 0.08)), ink: Theme.ink3) }
}

/// An icon and a word on one line, for the inside of a pill.
struct WLabel: View {
  let symbol: String
  let text: String

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
      Text(text)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }
}

/// A short line of small gray text under a title.
struct WCaption: View {
  let text: String
  var color: Color = Theme.ink2

  var body: some View {
    Text(text)
      .font(.system(size: 12))
      .foregroundStyle(color)
      .multilineTextAlignment(.center)
      .lineLimit(3)
      .minimumScaleFactor(0.85)
  }
}
