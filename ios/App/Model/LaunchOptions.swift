import Foundation

/// Launch arguments for demos, screenshots and tests, e.g. `-demo 1 -scene alarm-siren -open alarm`.
/// None of them do anything in a normal launch.
struct LaunchOptions {
  private let d = UserDefaults.standard

  var demo: Bool { d.bool(forKey: "demo") }
  var scene: DemoBackend.Scene {
    let raw = (d.string(forKey: "scene") ?? "").replacingOccurrences(of: "-", with: "")
    return DemoBackend.Scene.allCases.first { $0.rawValue.lowercased() == raw.lowercased() } ?? .idle
  }
  /// mac, alarm, records, record, settings, privacy, faq, start, paywall, share, evidence
  var open: String? { d.string(forKey: "open") }
  var pro: Bool { d.bool(forKey: "pro") }
  var notifOff: Bool { d.bool(forKey: "notifOff") }
  var onboardingStep: Onboarding.Step? { d.string(forKey: "onb").flatMap(Onboarding.Step.init(rawValue:)) }
  /// Page state to show: loading, error, offline (the phone's own network).
  var pageState: String? { d.string(forKey: "pstate") }
}

