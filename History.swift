import Foundation

/// How a session ended.
enum Disarm: String, Codable {
  case fingerprint, unlock, password, escape, stopped, sensorsSilent, tapFailed
}

/// One armed stretch: for the panel's Recent list and the welcome-back summary.
struct Session: Codable {
  var armed: Date
  var ended: Date
  var trigger: Trigger?
  var triggeredAt: Date?
  var disarm: Disarm
  var bumps: Int
  var softSeconds: Int
  var sirenSeconds: Int
  var photos: Int
  var clip: String?
  var test: Bool

  /// The line under "Recent": "Away 25 min, nobody touched it".
  var line: String {
    if let trigger { return trigger.headline + " · " + disarm.phrase }
    if bumps > 0 { return bumps == 1 ? L("Ignored 1 bump") : L("Ignored %ld bumps", bumps) }
    return L("%@, nobody touched it", Clock.away(ended.timeIntervalSince(armed)))
  }

  /// What the notice says as the fog clears.
  var welcome: Welcome {
    guard let trigger else {
      return Welcome(
        title: L("Welcome back"),
        sub: L("%@. Nobody touched it.", Clock.away(ended.timeIntervalSince(armed))),
        chips: [bumps == 0 ? L("All quiet") : bumps == 1 ? L("Ignored 1 bump") : L("Ignored %ld bumps", bumps),
                L("Nothing was recorded")],
        alarmed: false)
    }
    var chips: [String] = []
    if photos > 0 {
      chips.append(photos == 1 ? L("1 photo sent to your phone") : L("%ld photos sent to your phone", photos))
    } else if clip != nil {
      chips.append(L("Saved a recording on this Mac"))
    }
    if test {
      chips.append(L("Test mode: stayed silent"))
    } else if sirenSeconds > 0 {
      chips.append(L("The siren sounded for %ld s", sirenSeconds))
    } else if softSeconds > 0 {
      chips.append(L("Only the soft beeps played"))
    }
    return Welcome(title: L("Disarmed"), sub: trigger.sentence(at: triggeredAt ?? armed), chips: chips, alarmed: true)
  }
}

struct Welcome: Equatable {
  var title: String
  var sub: String
  var chips: [String]
  var alarmed: Bool
}

/// The last 30 sessions, newest first, in Application Support.
enum History {
  static let file = GuardApp.supportDir.appendingPathComponent("history.json")

  static func load() -> [Session] {
    guard let data = try? Data(contentsOf: file) else { return [] }
    return (try? JSONDecoder().decode([Session].self, from: data)) ?? []
  }

  static func add(_ session: Session) {
    let all = Array(([session] + load()).prefix(30))
    try? FileManager.default.createDirectory(at: GuardApp.supportDir, withIntermediateDirectories: true)
    do { try JSONEncoder().encode(all).write(to: file, options: .atomic) } catch { log("history not saved: \(error)") }
  }
}
