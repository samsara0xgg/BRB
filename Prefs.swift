import Foundation

/// Where the Mac is left, picked in the panel. Sets how much movement counts as someone taking it
/// (audit M5).
enum Place: String, CaseIterable, Codable {
  case library, cafe, transit

  var title: String {
    switch self {
    case .library: L("Library")
    case .cafe: L("Café")
    case .transit: L("On the go")
    }
  }

  /// The SF Symbol on the place picker.
  var symbol: String {
    switch self {
    case .library: "books.vertical"
    case .cafe: "cup.and.saucer"
    case .transit: "tram"
    }
  }

  /// What counts here, under the picker.
  var hint: String {
    switch self {
    case .library: L("Quiet table: a firm nudge or a lift sounds the alarm")
    case .cafe: L("Busy table: bumps are ignored, carrying it is not")
    case .transit: L("Moving vehicle: only tilt, the lid, the charger and touch count")
    }
  }

  /// Library: the calibrated knobs. Café: tables get bumped, so movement has to be firmer and last
  /// longer. On the go: a train or a bus shakes all the time, so only tilt, the lid, the charger and
  /// input count, and tilt gets more room for braking and bends.
  func motionDetector() -> MotionDetector {
    var d = MotionDetector()
    switch self {
    case .library: break
    case .cafe:
      d.shakeLimit = 0.08
      d.sustainFraction = 0.6
    case .transit:
      d.detectsShaking = false
      d.tiltLimit = 20
    }
    return d
  }
}

/// The panel's settings, kept in UserDefaults.
enum Prefs {
  static let noteLimit = 24
  private static let d = UserDefaults.standard

  static var place: Place {
    get { d.string(forKey: "place").flatMap(Place.init(rawValue:)) ?? .library }
    set { d.set(newValue.rawValue, forKey: "place") }
  }

  /// Shown on the notice as a chip; empty shows none.
  static var note: String {
    get { d.string(forKey: "note") ?? "" }
    set { d.set(String(newValue.prefix(noteLimit)), forKey: "note") }
  }

  /// The next session runs silent (speakers pinned muted); a disarm switches it off again (audit H1).
  static var testMode: Bool {
    get { d.bool(forKey: "testMode") }
    set { d.set(newValue, forKey: "testMode") }
  }

  /// The three-card introduction has been seen (or skipped): until then the panel opens on it, and
  /// the first launch opens the panel by itself.
  static var introSeen: Bool {
    get { d.bool(forKey: "introSeen") }
    set { d.set(newValue, forKey: "introSeen") }
  }

  /// When the panel last showed the alarms: a newer real alarm puts a red dot on the menu-bar
  /// shield and "New" on its Recent row. Unset (before this existed) counts as now.
  static var alarmsSeenAt: Date {
    get {
      if let date = d.object(forKey: "alarmsSeenAt") as? Date { return date }
      let now = Date()
      d.set(now, forKey: "alarmsSeenAt")
      return now
    }
    set { d.set(newValue, forKey: "alarmsSeenAt") }
  }

  /// The frosted screen while armed. Off: the old invisible mode, the menu bar icon shows the state.
  static var veil: Bool {
    get { d.object(forKey: "veil") as? Bool ?? true }
    set { d.set(newValue, forKey: "veil") }
  }
}
