import AppIntents
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

// MARK: - Colors

enum WStyle {
  /// The widget's background: dark navy or white, tinted red or orange while an alarm runs.
  static func background(for look: Look?) -> Color {
    switch look {
    case .some(.alarm): return Color.dyn(0x3a0f16, 0xffe4e6)
    case .some(.warn): return Color.dyn(0x3d230d, 0xffeadb)
    default: return Color.dyn(0x1e2436, 0xffffff)
    }
  }

  /// The color of a Mac's status line: amber while guarding, red in an alarm, quiet when idle.
  static func status(for look: Look) -> Color {
    switch look {
    case .idle, .test: return Theme.ink2
    default: return Theme.text(for: look)
    }
  }

  /// The always-dark colors of the Live Activity and the Dynamic Island.
  static let darkAmber = Theme.amber
  static let darkRed = Color(hex: 0xff6b72)
  static let darkOrange = Color(hex: 0xffa060)
  static let darkGreen = Color(hex: 0x5be39a)
  static let darkGray = Color(hex: 0x9aa1b5)
}

// MARK: - Words

enum WText {
  /// The big word: what the Mac is doing now. While arming the countdown is its own number, so this says the stage.
  static func title(_ s: MacSnapshot, now: Date) -> String {
    s.look == .arming ? t("la_arm") : s.title(now: now.ms)
  }

  /// The line under a Mac's name.
  static func line(_ s: MacSnapshot, now: Date) -> String {
    s.look == .idle ? s.subtitle(now: now.ms) : s.plain(now: now.ms)
  }
}

// MARK: - Clocks

/// A clock that keeps running without the widget being refreshed.
enum WClockKind {
  case countdown(Date)
  case elapsed(Date)

  /// The clock for a Mac: the countdown to guarding or to the siren, time on guard, time since the alarm began.
  static func of(_ s: MacSnapshot) -> WClockKind? {
    let st = s.state
    switch s.look {
    case .arming:
      if let end = st.armEnd { return WClockKind.countdown(end.date) }
      return nil
    case .warn:
      if let end = st.softEnd { return WClockKind.countdown(end.date) }
      return nil
    case .alarm:
      if let at = st.at { return WClockKind.elapsed(at.date) }
      return nil
    case .armed, .partial, .test:
      if st.since > 0 { return WClockKind.elapsed(st.since.date) }
      return nil
    default:
      return nil
    }
  }
}

struct WClockView: View {
  var kind: WClockKind
  var now: Date
  var size: CGFloat = 28
  var color: Color = Theme.amber
  var width: CGFloat? = nil
  var alignment: Alignment = .trailing

  var body: some View {
    clock
      .font(.rounded(size, .semibold))
      .monospacedDigit()
      .foregroundStyle(color)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .multilineTextAlignment(.trailing)
      .frame(width: width, alignment: alignment)
  }

  private var clock: Text {
    switch kind {
    case .countdown(let end):
      return Text(timerInterval: Swift.min(now, end)...end, countsDown: true)
    case .elapsed(let start):
      return Text(Swift.min(start, now), style: .timer)
    }
  }
}

// MARK: - Buttons

struct WPill: View {
  enum Style { case amber, ghost, red, orange }

  var title: String
  var symbol: String? = nil
  var style: Style = .ghost
  var height: CGFloat = 34

  private var fill: AnyShapeStyle {
    switch style {
    case .amber:
      return AnyShapeStyle(LinearGradient(colors: [Theme.amberHi, Theme.amberDeep], startPoint: .top, endPoint: .bottom))
    case .ghost: return AnyShapeStyle(Theme.cardHi)
    case .red: return AnyShapeStyle(Theme.red)
    case .orange: return AnyShapeStyle(Theme.orange)
    }
  }

  private var ink: Color {
    switch style {
    case .amber: return Theme.amberInk
    case .ghost: return Theme.ink
    case .red, .orange: return Color.white
    }
  }

  var body: some View {
    HStack(spacing: 5) {
      if let symbol {
        Image(systemName: symbol).font(.system(size: 12, weight: .bold))
      }
      Text(title)
        .font(.system(size: 13.5, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .foregroundStyle(ink)
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .background(fill, in: Capsule())
  }
}

/// The button a Mac's state calls for: Start, Cancel, Stop, or Stop siren. It runs the intent in the widget,
/// without opening the app. States that need the app get a pill that looks like a button; the widget's own
/// link opens the app when it is tapped.
struct WActionButton: View {
  var snap: MacSnapshot
  var height: CGFloat = 34

  private var isWarning: Bool { snap.alarmPhase == .warn }
  private var canHush: Bool { (snap.alarmPhase == .warn || snap.alarmPhase == .siren) && !snap.state.test }
  private var hushTitle: String { isWarning ? t("ab_hushWarn") : t("ab_stop") }
  private var hushStyle: WPill.Style { isWarning ? WPill.Style.orange : WPill.Style.red }

  var body: some View {
    if !BRBGate.unlocked {
      WPill(title: t("upgrade"), symbol: "lock.fill", style: .ghost, height: height)
    } else {
      switch snap.look {
      case .alarm, .warn:
        if canHush {
          Button(intent: HushSirenIntent(macID: snap.id)) {
            WPill(title: hushTitle, symbol: "speaker.slash.fill", style: hushStyle, height: height)
          }
          .buttonStyle(.plain)
        } else {
          WPill(title: t("btn_openAlarm"), symbol: "exclamationmark.triangle.fill", style: .red, height: height)
        }
      case .arming:
        Button(intent: CancelArmingIntent(macID: snap.id)) {
          WPill(title: t("btn_cancel"), style: .ghost, height: height)
        }
        .buttonStyle(.plain)
      case .armed, .partial, .test:
        Button(intent: StopGuardingIntent(macID: snap.id)) {
          WPill(title: t("btn_stopGuard"), symbol: "faceid", style: .ghost, height: height)
        }
        .buttonStyle(.plain)
      case .offline:
        // The title already says offline; the pill says since when.
        WPill(title: WText.line(snap, now: Date()), style: .ghost, height: height)
      case .idle:
        Button(intent: StartGuardingIntent(macID: snap.id)) {
          WPill(title: t("btn_start"), symbol: "shield.fill", style: .amber, height: height)
        }
        .buttonStyle(.plain)
      }
    }
  }
}

// MARK: - Photos

enum WPhoto {
  /// The cached alarm photo, shrunk so a Live Activity doesn't hold a full-size picture in memory.
  static func thumbnail(macID: String, ms: Ms, maxPixel: Int = 320) -> UIImage? {
    guard ms > 0, let url = BRBPhotoCache.fileURL(macID: macID, ms: ms),
      let source = CGImageSourceCreateWithURL(url as CFURL, nil)
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: cg)
  }
}

/// The newest alarm photo in a rounded frame, or nothing.
struct WPhotoView: View {
  var macID: String
  var ms: Ms
  var width: CGFloat
  var height: CGFloat
  var radius: CGFloat = 12

  var body: some View {
    if let image = WPhoto.thumbnail(macID: macID, ms: ms) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityHidden(true)
    }
  }
}
