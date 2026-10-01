import Foundation

/// A UI string in the Mac's language. English is the base; `Resources/zh-Hans.lproj` has the Chinese.
/// The key is the English text itself, so a missing translation still reads right.
func L(_ key: String, _ args: CVarArg...) -> String {
  let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
  return args.isEmpty ? format : String(format: format, arguments: args)
}

enum Clock {
  /// "14:32", or "2:32 PM" where the locale says so.
  static let time: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
  }()

  static let day: DateFormatter = {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate("MMMd")
    return f
  }()

  /// "Today 11:40", "Yesterday 16:12", "Sep 27".
  static func when(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return L("Today %@", time.string(from: date)) }
    if calendar.isDateInYesterday(date) { return L("Yesterday %@", time.string(from: date)) }
    return day.string(from: date)
  }

  /// "Away 42 min".
  static func away(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 1 { return L("Away under a minute") }
    if minutes < 90 { return L("Away %ld min", minutes) }
    return L("Away %ld h %ld min", minutes / 60, minutes % 60)
  }
}

extension Trigger {
  /// The push title, and the headline on the phone page and in the panel's Recent list.
  var headline: String {
    switch self {
    case .lifted: L("Your Mac was picked up")
    case .tilted: L("Your Mac was moved")
    case .lidClosed: L("The lid was closed")
    case .lidMoved: L("The lid was moved")
    case .charger: L("The charger was unplugged")
    case .powerKey: L("The power button was pressed")
    case .keyboard: L("Someone touched the keyboard")
    case .trackpad: L("Someone touched the trackpad")
    case .finger: L("Someone tried a fingerprint")
    case .restarted: L("The alarm resumed after a restart")
    }
  }

  /// The welcome-back line after an alarm: "At 14:32, someone picked up your Mac".
  func sentence(at date: Date) -> String {
    let t = Clock.time.string(from: date)
    return switch self {
    case .lifted: L("At %@, someone picked up your Mac", t)
    case .tilted: L("At %@, someone moved your Mac", t)
    case .lidClosed: L("At %@, someone closed the lid", t)
    case .lidMoved: L("At %@, someone moved the lid", t)
    case .charger: L("At %@, someone unplugged the charger", t)
    case .powerKey: L("At %@, someone pressed the power button", t)
    case .keyboard: L("At %@, someone touched the keyboard", t)
    case .trackpad: L("At %@, someone touched the trackpad", t)
    case .finger: L("At %@, someone tried a fingerprint", t)
    case .restarted: L("At %@, the alarm resumed after a restart", t)
    }
  }
}

extension Disarm {
  var phrase: String {
    switch self {
    case .fingerprint: L("Disarmed with Touch ID")
    case .unlock: L("Disarmed by unlocking")
    case .password: L("Disarmed with Touch ID or password")
    case .escape: L("Cancelled")
    case .stopped: L("Guarding was stopped")
    case .sensorsSilent: L("Stopped: the sensors sent no data")
    case .tapFailed: L("Restarted to watch the keyboard")
    }
  }
}
