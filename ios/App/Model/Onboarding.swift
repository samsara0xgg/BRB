import Foundation

/// Where the first-run flow is. `scan`, `code` and the error pages are also reached later from "Pair a new Mac".
struct Onboarding: Equatable {
  enum Step: String {
    case welcome, notif, crit, scan, code, paired, done
    case camdenied, expired, macoffline, nomac, notifoff
  }
  enum ScanPhase { case scanning, pairing }

  var step: Step
  /// The welcome card, 0 to 2.
  var page = 0
  var phase: ScanPhase = .scanning
  var code = ""
  /// The six digits were not a pairing code (or an old one).
  var codeError = false
  /// Set once a Mac was claimed.
  var pairedID: String?
  var testState: TestState = .idle
  /// The pairing is for an extra Mac (the app is already set up), so it ends with the Mac's page, not the tour.
  var extra = false
  /// The step to go back to from `nomac`.
  var cameFrom: Step = .scan
  /// Opened from Settings to look at the welcome cards again: it ends after the last one.
  var replay = false

  enum TestState { case idle, sending, got }
}

/// What this build can do that depends on Apple having approved the app for it.
enum Capabilities {
  /// Critical alerts need an entitlement Apple grants on request. Builds that have it set the
  /// CRITICAL_ALERTS compilation condition; without it BRB uses Time Sensitive alerts and hides the switch.
  static let criticalAlerts: Bool = {
    #if CRITICAL_ALERTS
      return true
    #else
      return false
    #endif
  }()
}
