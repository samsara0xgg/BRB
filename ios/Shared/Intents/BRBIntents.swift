import AppIntents
import Foundation

/// A sentence an intent says or shows. Interpolating keeps it a plain string at run time.
func brbDialog(_ text: String) -> IntentDialog {
  "\(text)"
}

// MARK: - Start

struct StartGuardingIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource(
    "wi_start_title", defaultValue: "Start guarding", table: "Widgets")
  static var description = IntentDescription(
    LocalizedStringResource("wi_start_desc", defaultValue: "Starts guarding one of your Macs.", table: "Widgets"))

  @Parameter(title: LocalizedStringResource("wi_p_mac", defaultValue: "Mac", table: "Widgets"))
  var mac: MacEntity?

  @Parameter(title: LocalizedStringResource("shPlace", defaultValue: "Place"))
  var place: PlaceChoice?

  init() {}

  init(macID: String) {
    self.mac = MacEntity(id: macID, name: "")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let report = await BRBCommander.startGuarding(macID: mac?.id, place: place?.place)
    return .result(dialog: brbDialog(report.text))
  }
}

// MARK: - Stop

struct StopGuardingIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource(
    "wi_stop_title", defaultValue: "Stop guarding", table: "Widgets")
  static var description = IntentDescription(
    LocalizedStringResource(
      "wi_stop_desc", defaultValue: "Stops guarding, or disarms an alarm. Your phone has to be unlocked.", table: "Widgets"))

  /// Stopping is the one thing a thief with a locked phone must not be able to do.
  static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(title: LocalizedStringResource("wi_p_mac", defaultValue: "Mac", table: "Widgets"))
  var mac: MacEntity?

  init() {}

  init(macID: String) {
    self.mac = MacEntity(id: macID, name: "")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let report = await BRBCommander.stopGuarding(macID: mac?.id)
    return .result(dialog: brbDialog(report.text))
  }
}

// MARK: - Cancel the countdown

/// The Cancel button on the widget and in the Dynamic Island while the 5 second countdown runs. It can only
/// cancel a countdown, so it asks for no authentication, and Shortcuts doesn't list it.
struct CancelArmingIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource(
    "wi_cancel_title", defaultValue: "Cancel the countdown", table: "Widgets")
  static var isDiscoverable: Bool = false

  @Parameter(title: LocalizedStringResource("wi_p_mac", defaultValue: "Mac", table: "Widgets"))
  var mac: MacEntity?

  init() {}

  init(macID: String) {
    self.mac = MacEntity(id: macID, name: "")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let report = await BRBCommander.stopGuarding(macID: mac?.id, allowDisarm: false)
    return .result(dialog: brbDialog(report.text))
  }
}

// MARK: - Hush

struct HushSirenIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource(
    "wi_hush_title", defaultValue: "Stop the siren", table: "Widgets")
  static var description = IntentDescription(
    LocalizedStringResource(
      "wi_hush_desc", defaultValue: "Silences the siren on a Mac. It stays locked and keeps filming.", table: "Widgets"))

  @Parameter(title: LocalizedStringResource("wi_p_mac", defaultValue: "Mac", table: "Widgets"))
  var mac: MacEntity?

  init() {}

  init(macID: String) {
    self.mac = MacEntity(id: macID, name: "")
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let report = await BRBCommander.hushSiren(macID: mac?.id)
    return .result(dialog: brbDialog(report.text))
  }
}

// MARK: - Questions

struct GuardStatusIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource(
    "wi_status_title", defaultValue: "Get guard status", table: "Widgets")
  static var description = IntentDescription(
    LocalizedStringResource(
      "wi_status_desc", defaultValue: "Tells you whether your Macs are guarded.", table: "Widgets"))

  @Parameter(title: LocalizedStringResource("wi_p_mac", defaultValue: "Mac", table: "Widgets"))
  var mac: MacEntity?

  init() {}

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let report = await BRBCommander.status(macID: mac?.id)
    return .result(value: report.text, dialog: brbDialog(report.text))
  }
}

struct LatestSessionIntent: AppIntent {
  static var title: LocalizedStringResource = LocalizedStringResource(
    "wi_latest_title", defaultValue: "Get the latest session", table: "Widgets")
  static var description = IntentDescription(
    LocalizedStringResource(
      "wi_latest_desc", defaultValue: "Tells you how your last guarded session went.", table: "Widgets"))

  @Parameter(title: LocalizedStringResource("wi_p_mac", defaultValue: "Mac", table: "Widgets"))
  var mac: MacEntity?

  init() {}

  func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
    let report = await BRBCommander.latest(macID: mac?.id)
    return .result(value: report.text, dialog: brbDialog(report.text))
  }
}
