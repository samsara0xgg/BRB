import Foundation

/// Milliseconds since 1970, what the relay and the Mac speak.
typealias Ms = Int64

func nowMs() -> Ms { Ms(Date().timeIntervalSince1970 * 1000) }
extension Ms { var date: Date { Date(timeIntervalSince1970: Double(self) / 1000) } }
extension Date { var ms: Ms { Ms(timeIntervalSince1970 * 1000) } }

// MARK: - Copy

/// The language the app speaks right now (the bundle's best match, so tests and screenshots can pick one).
var isZh: Bool { (Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("zh") }

/// The string tables the app reads, in order: the main one, then the ones the widgets and the Watch keep.
private let stringTables = ["Localizable", "Widgets", "Watch"]
private let missing = "\u{1}missing\u{1}"

private func localized(_ key: String) -> String {
  for table in stringTables {
    let s = Bundle.main.localizedString(forKey: key, value: missing, table: table)
    if s != missing { return s }
  }
  return key
}

/// Looks a string up in Localizable.strings (or Widgets.strings, Watch.strings) and fills `%1$@` / `%1$d` from `args`.
func t(_ key: String, _ args: CVarArg...) -> String {
  let format = localized(key)
  return args.isEmpty ? format : String(format: format, locale: Locale.current, arguments: args)
}

/// `t` for a plural (Localizable.stringsdict) key: `tn("n_bumps", 3)` is "3 bumps".
func tn(_ key: String, _ n: Int) -> String {
  String(format: localized(key), locale: Locale.current, n)
}

// MARK: - Time and durations

private func formatter(_ template: String) -> DateFormatter {
  let f = DateFormatter()
  f.locale = Locale.current
  f.setLocalizedDateFormatFromTemplate(template)
  return f
}

enum Fmt {
  /// 14:05 or 2:05 PM, as the phone prefers.
  static func hm(_ ms: Ms) -> String { formatter("jmm").string(from: ms.date) }
  static func hms(_ ms: Ms) -> String { formatter("jmmss").string(from: ms.date) }

  /// 0:42 or 1:02:09, a running clock.
  static func elapsed(_ ms: Ms) -> String {
    let s = Int(max(0, ms) / 1000), h = s / 3600, m = s % 3600 / 60, ss = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, ss) : String(format: "%d:%02d", m, ss)
  }

  /// "2 h 5 min" / "2 小时 5 分钟".
  static func duration(_ ms: Ms) -> String {
    if ms < 60_000 { return t("lt1m") }
    let m = Int((Double(ms) / 60_000).rounded()), h = m / 60, mm = m % 60
    if isZh { return h > 0 ? (mm > 0 ? "\(h) 小时 \(mm) 分钟" : "\(h) 小时") : "\(m) 分钟" }
    return h > 0 ? (mm > 0 ? "\(h) h \(mm) min" : "\(h) h") : "\(m) min"
  }

  /// "just now", "5 min ago", "3 h ago", "2 d ago".
  static func ago(_ ms: Ms, now: Ms = nowMs()) -> String {
    let m = Int((now - ms) / 60_000)
    if m < 1 { return t("justNow") }
    if m < 60 { return isZh ? "\(m) 分钟前" : "\(m) min ago" }
    let h = m / 60
    if h < 24 { return isZh ? "\(h) 小时前" : "\(h) h ago" }
    let d = h / 24
    return isZh ? "\(d) 天前" : "\(d) d ago"
  }

  /// Seconds as "42s" or "2m 5s".
  static func secs(_ s: Int) -> String {
    s < 60 ? t("secs_s", s) : t("secs_ms", s / 60, s % 60)
  }

  static func dayKey(_ ms: Ms) -> DateComponents {
    Calendar.current.dateComponents([.year, .month, .day], from: ms.date)
  }

  /// Today, Yesterday, or "Tuesday, Oct 7".
  static func dayLabel(_ ms: Ms, now: Ms = nowMs()) -> String {
    let cal = Calendar.current
    if cal.isDate(ms.date, inSameDayAs: now.date) { return t("today") }
    if cal.isDate(ms.date, inSameDayAs: now.date.addingTimeInterval(-86_400)) { return t("yesterday") }
    return formatter("EEEEMMMd").string(from: ms.date)
  }

  static func fullDate(_ ms: Ms) -> String { formatter("yMMMd").string(from: ms.date) }

  /// "2 hours" / "2 小时" for the share card.
  static func hours(_ h: Int) -> String { tn("hrs", h) }
}


extension Double { func clamped(_ lo: Double = 0, _ hi: Double = 1) -> Double { Swift.max(lo, Swift.min(hi, self)) } }
