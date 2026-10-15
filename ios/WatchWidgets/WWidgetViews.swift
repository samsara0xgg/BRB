import SwiftUI
import WidgetKit

/// What the complication shows for an entry: the shield and a short word, in each accessory shape.
struct WWidgetView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetRenderingMode) private var renderingMode
  let entry: WWidgetEntry

  var body: some View {
    switch family {
    case .accessoryCorner:
      corner
    case .accessoryRectangular:
      rectangular
    case .accessoryInline:
      inline
    default:
      circular
    }
  }

  // MARK: what to say

  private var snap: MacSnapshot? { entry.snapshot }

  private var locked: Bool { !entry.pro }

  private var look: Look { snap?.look ?? .idle }

  /// The shield in full color where the face allows it, in one color otherwise.
  private var mono: Bool { renderingMode != .fullColor }

  /// One short word.
  private var word: String {
    if locked { return t("wv_needCloud") }
    guard let snap else { return t("ww_pairShort") }
    switch snap.look {
    case .idle: return t("st_idle")
    case .arming: return t("la_arm")
    case .armed: return t("st_armed")
    case .partial: return t("st_partial")
    case .test: return t("st_test")
    case .offline: return t("st_offline")
    case .warn, .alarm: return snap.trigger.title
    }
  }

  /// The line under the word, with times that do not go stale.
  private var detail: String {
    if locked { return t("wv_cloudBtn") }
    guard let snap else { return t("ww_emptyT") }
    let s = snap.state
    switch snap.look {
    case .idle:
      guard let end = s.lastEnd else { return t("sub_never") }
      return t("sub_idle", Fmt.hm(end))
    case .arming: return t("sub_arming")
    case .armed, .partial, .test: return t("ww_since", Fmt.hm(s.since))
    case .offline: return t("sub_offline", Fmt.hm(snap.lastSeenTime))
    case .warn, .alarm: return t("ww_since", Fmt.hm(s.at ?? snap.lastSeenTime))
    }
  }

  private var symbol: String {
    if locked { return "lock.fill" }
    switch look {
    case .idle: return "shield"
    case .offline: return "wifi.slash"
    case .warn, .alarm: return "exclamationmark.triangle.fill"
    default: return "shield.fill"
    }
  }

  // MARK: pieces

  @ViewBuilder
  private func shield(_ size: CGFloat) -> some View {
    if locked {
      Image(systemName: "lock.fill")
        .font(.system(size: size * 0.7, weight: .semibold))
        .widgetAccentable()
    } else if snap == nil {
      ShieldView(look: .idle, size: size, mono: true)
        .widgetAccentable()
    } else {
      ShieldView(look: look.shield, size: size, mono: mono)
        .widgetAccentable()
    }
  }

  // MARK: families

  private var circular: some View {
    ZStack {
      AccessoryWidgetBackground()
      shield(30)
    }
  }

  private var corner: some View {
    shield(30)
      .widgetLabel {
        Text(word)
      }
  }

  private var rectangular: some View {
    HStack(spacing: 8) {
      shield(32)
      VStack(alignment: .leading, spacing: 1) {
        Text(word)
          .font(.system(size: 14, weight: .bold))
          .widgetAccentable()
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(snap?.name ?? "BRB")
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
        Text(detail)
          .font(.system(size: 11))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      Spacer(minLength: 0)
    }
  }

  private var inline: some View {
    Label(word, systemImage: symbol)
  }
}
