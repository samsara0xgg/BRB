import UIKit

/// Stand-ins for the Mac's camera in demo mode: a few simple scenes drawn with Core Graphics.
enum DemoArt {
  enum Mode { case still, approach, touch, carried, returned }

  static func image(at ms: Ms, mode: Mode, place: Place, size: CGSize = CGSize(width: 320, height: 200), stamp: Bool = true) -> UIImage {
    let seed = Double(ms % 100_000) / 1000
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { ctx in
      let c = ctx.cgContext
      let w = size.width, h = size.height
      // room
      let tops: [Place: (UIColor, UIColor)] = [
        .cafe: (UIColor(red: 0.36, green: 0.27, blue: 0.2, alpha: 1), UIColor(red: 0.16, green: 0.12, blue: 0.1, alpha: 1)),
        .library: (UIColor(red: 0.2, green: 0.26, blue: 0.36, alpha: 1), UIColor(red: 0.09, green: 0.11, blue: 0.17, alpha: 1)),
        .transit: (UIColor(red: 0.28, green: 0.3, blue: 0.34, alpha: 1), UIColor(red: 0.1, green: 0.11, blue: 0.14, alpha: 1)),
      ]
      let (a, b) = tops[place] ?? tops[.cafe]!
      let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1])!
      c.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: h), options: [])
      // window glow
      c.setFillColor(UIColor(white: 1, alpha: 0.08).cgColor)
      c.fill(CGRect(x: w * 0.62, y: h * 0.1, width: w * 0.28, height: h * 0.34))
      // table
      c.setFillColor(UIColor(white: 0, alpha: 0.35).cgColor)
      c.fill(CGRect(x: 0, y: h * 0.72, width: w, height: h * 0.28))
      // the Mac's own lid edge
      c.setFillColor(UIColor(white: 0.1, alpha: 0.9).cgColor)
      c.fill(CGRect(x: w * 0.3, y: h * 0.84, width: w * 0.4, height: h * 0.16))

      func person(cx: CGFloat, top: CGFloat, scale: CGFloat, tint: UIColor) {
        c.setFillColor(tint.cgColor)
        c.fillEllipse(in: CGRect(x: cx - 18 * scale, y: top, width: 36 * scale, height: 42 * scale))
        let body = UIBezierPath(
          roundedRect: CGRect(x: cx - 46 * scale, y: top + 46 * scale, width: 92 * scale, height: 130 * scale),
          byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 40 * scale, height: 40 * scale))
        tint.setFill()
        body.fill()
      }
      let tint = UIColor(red: 0.12, green: 0.1, blue: 0.12, alpha: 0.92)
      switch mode {
      case .still: break
      case .approach:
        person(cx: w * 0.5 + CGFloat(sin(seed)) * 6, top: h * 0.2, scale: 0.8 + CGFloat(seed.truncatingRemainder(dividingBy: 5)) * 0.04, tint: tint)
      case .touch:
        person(cx: w * 0.5, top: h * 0.14, scale: 1.0, tint: tint)
        c.setFillColor(UIColor(red: 0.55, green: 0.42, blue: 0.36, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: w * 0.44, y: h * 0.74, width: 44, height: 26))
      case .carried:
        c.rotate(by: CGFloat(sin(seed * 2)) * 0.12)
        person(cx: w * 0.42, top: h * 0.1, scale: 1.25, tint: tint)
      case .returned:
        person(cx: w * 0.62, top: h * 0.16, scale: 0.9, tint: tint.withAlphaComponent(0.6))
      }
    }.withStamp(ms: ms, show: stamp)
  }
}

private extension UIImage {
  func withStamp(ms: Ms, show: Bool) -> UIImage {
    guard show else { return self }
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
      draw(at: .zero)
      let text = Fmt.hms(ms) as NSString
      let font = UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
      let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
      let tsize = text.size(withAttributes: attrs)
      UIColor(white: 0, alpha: 0.5).setFill()
      UIRectFill(CGRect(x: 6, y: size.height - 17, width: tsize.width + 8, height: 12))
      text.draw(at: CGPoint(x: 10, y: size.height - 17), withAttributes: attrs)
    }
  }
}
