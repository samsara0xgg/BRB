import AppIntents
import SwiftUI
import WidgetKit

// The iOS 18 control: one toggle for the focus Mac, for Control Center, the Lock Screen and the Action button.

/// What the toggle needs to draw itself.
@available(iOS 18.0, *)
struct BRBControlValue: Sendable {
  var isOn: Bool
  /// The Mac the toggle acts on, empty when none is paired.
  var macID: String
  /// What the Mac is doing, in words, for the toggle's second line.
  var status: String
}

@available(iOS 18.0, *)
struct BRBControlProvider: ControlValueProvider {
  var previewValue: BRBControlValue {
    BRBControlValue(isOn: false, macID: "", status: t("st_idle"))
  }

  func currentValue() async throws -> BRBControlValue {
    guard BRBGate.unlocked else {
      return BRBControlValue(isOn: false, macID: "", status: t("wv_needCloud"))
    }
    let macs = await BRBLoader.snapshots(timeout: 3)
    guard let focus = BRBFocus.pick(macs) else {
      return BRBControlValue(isOn: false, macID: "", status: t("emptyDevT"))
    }
    let phase = focus.state.phase
    let on = phase == .arming || phase == .armed || phase == .triggered
    let status: String
    switch focus.look {
    case .idle: status = t("st_idle")
    case .arming: status = t("la_arm")
    case .armed, .partial: status = t("st_armed")
    case .test: status = t("st_test")
    case .offline: status = t("st_offline")
    case .warn, .alarm: status = focus.trigger.title
    }
    return BRBControlValue(isOn: on, macID: focus.id, status: status)
  }
}

/// Turning the toggle on starts guarding, off stops it (or disarms an alarm). Stopping needs the phone unlocked,
/// so both directions do.
@available(iOS 18.0, *)
struct SetGuardingIntent: SetValueIntent {
  static var title: LocalizedStringResource = LocalizedStringResource(
    "wi_set_title", defaultValue: "Guarding", table: "Widgets")
  static var isDiscoverable: Bool = false
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(title: LocalizedStringResource("wi_set_title", defaultValue: "Guarding", table: "Widgets"))
  var value: Bool

  @Parameter(title: LocalizedStringResource("wi_p_mac", defaultValue: "Mac", table: "Widgets"))
  var mac: MacEntity?

  init() {}

  init(macID: String) {
    self.mac = MacEntity(id: macID, name: "")
  }

  func perform() async throws -> some IntentResult {
    guard let id = mac?.id, !id.isEmpty else {
      await BRBWidgetRefresh.reloadNow()
      return .result()
    }
    if value {
      _ = await BRBCommander.startGuarding(macID: id, place: nil)
    } else {
      _ = await BRBCommander.stopGuarding(macID: id)
    }
    await BRBWidgetRefresh.reloadNow()
    return .result()
  }
}

@available(iOS 18.0, *)
struct BRBGuardControl: ControlWidget {
  static let kind = "com.allen.brb.guard"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: BRBGuardControl.kind, provider: BRBControlProvider()) { value in
      ControlWidgetToggle("Back in 5", isOn: value.isOn, action: SetGuardingIntent(macID: value.macID)) { isOn in
        Label(value.status, systemImage: isOn ? "shield.fill" : "shield")
      }
    }
    .displayName(LocalizedStringResource("wi_control_name", defaultValue: "Guarding", table: "Widgets"))
    .description(
      LocalizedStringResource("wi_control_desc", defaultValue: "Start or stop guarding your Mac.", table: "Widgets"))
  }
}
