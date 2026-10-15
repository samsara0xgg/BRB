import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - What the activity says

/// The Live Activity's content state turned into words, colors and buttons. The relay's pushes and the app's
/// own updates carry the same state (BRBActivityAttributes.ContentState).
struct WActivityModel {
  enum Stage { case arming, guarding, warn, siren, back, hushed, clear, offline }

  let state: BRBActivityAttributes.ContentState
  let macName: String
  let macID: String

  var stage: Stage {
    switch state.look {
    case "arming": return .arming
    case "warn": return .warn
    case "alarm": return .siren
    case "back": return .back
    case "hushed": return .hushed
    case "clear": return .clear
    case "offline": return .offline
    default: return .guarding
    }
  }

  /// An alarm of any kind is going on: the warning, the siren, put back, or silenced.
  var isAlarm: Bool {
    switch stage {
    case .warn, .siren, .back, .hushed: return true
    default: return false
    }
  }

  var shield: ShieldLook {
    switch stage {
    case .arming: return .arming
    case .guarding:
      if state.look == "partial" { return .partial }
      if state.look == "test" { return .test }
      return .armed
    case .warn: return .warn
    case .siren, .back, .hushed: return .alarm
    case .clear: return .clear
    case .offline: return .offline
    }
  }

  /// The color of the clock and the island's glow.
  var accent: Color {
    switch stage {
    case .arming, .guarding: return WStyle.darkAmber
    case .warn: return WStyle.darkOrange
    case .siren, .back, .hushed: return WStyle.darkRed
    case .clear: return WStyle.darkGreen
    case .offline: return WStyle.darkGray
    }
  }

  /// What the Lock Screen card is tinted with.
  var tint: Color {
    switch stage {
    case .warn: return Color(hex: 0x6b3208, opacity: 0.9)
    case .siren, .back, .hushed: return Color(hex: 0x5a0d1a, opacity: 0.9)
    case .clear: return Color(hex: 0x0b4a2a, opacity: 0.92)
    default: return Color(hex: 0x0e111a, opacity: 0.8)
    }
  }

  private var triggerTitle: String {
    let kind = state.trigger.flatMap { Trigger(rawValue: $0) }?.kind ?? Trigger.Kind.lift
    return (state.test ? t("alTestPre") : "") + kind.title
  }

  private var placeName: String { Place(rawValue: state.place)?.name ?? "" }

  /// "Guarding · Café", or what set the alarm off.
  var header: String {
    switch stage {
    case .guarding: return t("la_guard", placeName)
    case .warn, .siren, .back, .hushed: return triggerTitle
    default: return "BRB"
    }
  }

  var title: String {
    switch stage {
    case .arming: return t("la_arm")
    case .guarding:
      if state.look == "test" { return t("st_test") }
      return state.look == "partial" ? t("st_partial") : t("st_armed")
    case .warn: return t("wi_warnIn")
    case .siren: return state.test ? t("lb_test") : t("lb_siren")
    case .back: return t("lb_returned")
    case .hushed: return t("lb_muted")
    case .clear: return t("alH_done")
    case .offline: return t("st_offline")
    }
  }

  var subtitle: String {
    switch stage {
    case .arming: return t("sub_arming")
    case .guarding:
      let line = state.bumps > 0 ? t("sub_armed", "", tn("n_bumps", state.bumps)) : t("sub_armed0", "")
      return line.hasPrefix(" · ") ? String(line.dropFirst(3)) : line
    case .warn: return t("lb_warnS")
    case .siren: return state.test ? t("lb_testS") : t("lb_sirenS")
    case .back: return t("lb_returnedS")
    case .hushed: return t("lb_mutedS")
    case .clear:
      switch state.by ?? "" {
      case "phone", "face": return t("byS_face")
      case "watch": return t("byS_watch")
      default: return t("byS_touch")
      }
    case .offline: return t("offNote")
    }
  }

  /// The running clock: the countdown to guarding or to the siren, time on guard, time since the alarm began.
  var clock: WClockKind? {
    switch stage {
    case .arming: return state.armEnd > 0 ? WClockKind.countdown(state.armEnd.date) : nil
    case .warn: return state.softEnd > 0 ? WClockKind.countdown(state.softEnd.date) : nil
    case .siren: return state.at > 0 ? WClockKind.elapsed(state.at.date) : nil
    case .guarding: return state.since > 0 ? WClockKind.elapsed(state.since.date) : nil
    default: return nil
    }
  }

  var canHush: Bool { (stage == .warn || stage == .siren) && !state.test && BRBGate.unlocked }
  var canStop: Bool { stage == .guarding && BRBGate.unlocked }
  var canCancel: Bool { stage == .arming && BRBGate.unlocked }

  var hushTitle: String { stage == .warn ? t("ab_hushWarn") : t("ab_stop") }
  var openURL: URL { isAlarm ? BRBDeepLink.alarm(macID) : BRBDeepLink.mac(macID) }

  var compactSymbol: String {
    switch stage {
    case .back: return "checkmark.circle.fill"
    case .hushed: return "speaker.slash.fill"
    case .clear: return "checkmark"
    case .offline: return "wifi.slash"
    default: return "shield.fill"
    }
  }
}

// MARK: - The widget

struct BRBGuardActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BRBActivityAttributes.self) { context in
      let model = WActivityModel(
        state: context.state, macName: context.attributes.macName, macID: context.attributes.macId)
      BRBLockActivityView(model: model)
        .activityBackgroundTint(model.tint)
        .activitySystemActionForegroundColor(Color.white)
        .widgetURL(model.openURL)
    } dynamicIsland: { context in
      let model = WActivityModel(
        state: context.state, macName: context.attributes.macName, macID: context.attributes.macId)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          BRBIslandLeading(model: model)
        }
        DynamicIslandExpandedRegion(.trailing) {
          BRBIslandTrailing(model: model)
        }
        DynamicIslandExpandedRegion(.center) {
          BRBIslandCenter(model: model)
        }
        DynamicIslandExpandedRegion(.bottom) {
          BRBIslandBottom(model: model)
        }
      } compactLeading: {
        WShield(look: model.shield, size: 18)
      } compactTrailing: {
        BRBIslandCompactTrailing(model: model)
      } minimal: {
        WShield(look: model.shield, size: 18)
      }
      .keylineTint(model.accent)
      .widgetURL(model.openURL)
    }
  }
}

// MARK: - Lock Screen

struct WActivityButtonLabel: View {
  var title: String
  var symbol: String
  var prominent = false
  var height: CGFloat = 38

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
      Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
    }
    .foregroundStyle(prominent ? Color.black : Color.white)
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .background(prominent ? Color.white : Color.white.opacity(0.16), in: Capsule())
  }
}

struct BRBLockActivityView: View {
  let model: WActivityModel

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 9) {
        WShield(look: .armed, size: 22)
        Text(model.header)
          .font(.system(size: 14.5, weight: .semibold))
          .lineLimit(1)
        Spacer(minLength: 4)
        Text(model.macName)
          .font(.system(size: 12.5))
          .opacity(0.7)
          .lineLimit(1)
      }

      HStack(spacing: 12) {
        WShield(look: model.shield, size: 34)
        VStack(alignment: .leading, spacing: 1) {
          HStack(spacing: 6) {
            Text(model.title)
              .font(.system(size: 16, weight: .semibold))
              .lineLimit(1)
            if model.isAlarm, let clock = model.clock {
              WClockView(kind: clock, now: Date(), size: 16, color: model.accent, width: 60, alignment: .leading)
            }
          }
          Text(model.subtitle)
            .font(.system(size: 12.5))
            .opacity(0.72)
            .lineLimit(2)
        }
        Spacer(minLength: 4)
        trailing
      }

      actions
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .foregroundStyle(Color.white)
    .environment(\.colorScheme, .dark)
  }

  @ViewBuilder private var trailing: some View {
    if model.isAlarm {
      if model.state.photo > 0 {
        WPhotoView(macID: model.macID, ms: model.state.photo, width: 58, height: 44, radius: 10)
      }
    } else if let clock = model.clock {
      WClockView(kind: clock, now: Date(), size: 30, color: model.accent, width: 96, alignment: .trailing)
    }
  }

  @ViewBuilder private var actions: some View {
    if model.canHush {
      HStack(spacing: 8) {
        Button(intent: HushSirenIntent(macID: model.macID)) {
          WActivityButtonLabel(title: model.hushTitle, symbol: "speaker.slash.fill")
        }
        .buttonStyle(.plain)
        Link(destination: model.openURL) {
          WActivityButtonLabel(title: t("open"), symbol: "arrow.up.right.square")
        }
      }
    } else if model.isAlarm {
      Link(destination: model.openURL) {
        WActivityButtonLabel(title: t("open"), symbol: "arrow.up.right.square")
      }
    } else if model.canStop {
      Button(intent: StopGuardingIntent(macID: model.macID)) {
        WActivityButtonLabel(title: t("btn_stopGuard"), symbol: "faceid")
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - Dynamic Island

struct BRBIslandLeading: View {
  let model: WActivityModel

  var body: some View {
    if model.isAlarm && model.state.photo > 0 && WPhoto.thumbnail(macID: model.macID, ms: model.state.photo) != nil {
      WPhotoView(macID: model.macID, ms: model.state.photo, width: 62, height: 46, radius: 12)
    } else {
      WShield(look: model.shield, size: 34)
    }
  }
}

struct BRBIslandTrailing: View {
  let model: WActivityModel

  var body: some View {
    if let clock = model.clock {
      WClockView(kind: clock, now: Date(), size: 24, color: model.accent, width: 84, alignment: .trailing)
    }
  }
}

struct BRBIslandCenter: View {
  let model: WActivityModel

  var body: some View {
    VStack(spacing: 1) {
      Text(model.isAlarm ? model.header : model.title)
        .font(.system(size: 15, weight: .semibold))
        .lineLimit(1)
      Text(model.isAlarm ? model.title : model.subtitle)
        .font(.system(size: 12.5))
        .foregroundStyle(Color.white.opacity(0.62))
        .lineLimit(1)
      Text(model.macName)
        .font(.system(size: 12.5))
        .foregroundStyle(Color.white.opacity(0.62))
        .lineLimit(1)
    }
    .multilineTextAlignment(.center)
  }
}

struct BRBIslandBottom: View {
  let model: WActivityModel

  var body: some View {
    if model.canHush {
      HStack(spacing: 8) {
        Button(intent: HushSirenIntent(macID: model.macID)) {
          WActivityButtonLabel(title: model.hushTitle, symbol: "speaker.slash.fill", prominent: true, height: 44)
        }
        .buttonStyle(.plain)
        Link(destination: model.openURL) {
          WActivityButtonLabel(title: t("open"), symbol: "arrow.up.right.square", height: 44)
        }
      }
    } else if model.isAlarm {
      Link(destination: model.openURL) {
        WActivityButtonLabel(title: t("open"), symbol: "arrow.up.right.square", height: 44)
      }
    } else if model.canStop {
      HStack(spacing: 8) {
        Button(intent: StopGuardingIntent(macID: model.macID)) {
          WActivityButtonLabel(title: t("btn_stopGuard"), symbol: "faceid", height: 44)
        }
        .buttonStyle(.plain)
        Link(destination: model.openURL) {
          WActivityButtonLabel(title: t("open"), symbol: "arrow.up.right.square", prominent: true, height: 44)
        }
      }
    } else if model.canCancel {
      Button(intent: CancelArmingIntent(macID: model.macID)) {
        WActivityButtonLabel(title: t("btn_cancel"), symbol: "xmark", height: 44)
      }
      .buttonStyle(.plain)
    }
  }
}

struct BRBIslandCompactTrailing: View {
  let model: WActivityModel

  var body: some View {
    if let clock = model.clock {
      WClockView(kind: clock, now: Date(), size: 14, color: model.accent, width: 48, alignment: .trailing)
    } else {
      Image(systemName: model.compactSymbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(model.accent)
    }
  }
}
