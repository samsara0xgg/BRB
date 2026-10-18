import Foundation

// MARK: - What the Mac reports

enum Place: String, Codable, CaseIterable, Sendable {
  case library, cafe, transit

  var nameKey: String {
    switch self {
    case .library: return "pl_library"
    case .cafe: return "pl_cafe"
    case .transit: return "pl_road"
    }
  }
  var descKey: String {
    switch self {
    case .library: return "pd_library"
    case .cafe: return "pd_cafe"
    case .transit: return "pd_road"
    }
  }
  var name: String { t(nameKey) }
  var detail: String { t(descKey) }
  var symbol: String {
    switch self {
    case .library: return "books.vertical.fill"
    case .cafe: return "cup.and.saucer.fill"
    case .transit: return "car.fill"
    }
  }
}

enum Phase: String, Codable, Sendable { case idle, arming, armed, triggered }

/// While `triggered`: the voice warning, the siren, put back, or hushed by the owner.
enum Stage: String, Codable, Sendable { case soft, siren, back, hushed }

enum Trigger: String, Codable, Sendable {
  case lifted, tilted, lidClosed, lidMoved, charger, powerKey, keyboard, trackpad, finger, restarted

  /// The three wordings the app has: picked up, touched, pushed.
  enum Kind: String, Sendable { case lift, touch, nudge }

  var kind: Kind {
    switch self {
    case .keyboard, .trackpad, .finger: return .touch
    default: return .lift
    }
  }
  /// "Picked up" as a title and "picked up" inside a sentence.
  var title: String { t("tc_" + kind.rawValue) }
  var phrase: String { t("tn_" + kind.rawValue) }
  var headline: String { t("alH_" + kind.rawValue) }
}

extension Trigger.Kind {
  var title: String { t("tc_" + rawValue) }
  var phrase: String { t("tn_" + rawValue) }
  var headline: String { t("alH_" + rawValue) }
}

struct MacInfo: Equatable, Codable, Sendable {
  var name: String
  var model: String
  var batt: Int
  var chg: Bool
}

/// The four checks the Mac runs on itself. True is fine.
struct Health: Equatable, Codable, Sendable {
  var ax = true, cam = true, lid = true, mot = true
  static let keys = ["ax", "cam", "lid", "mot"]
  subscript(key: String) -> Bool {
    switch key {
    case "ax": return ax
    case "cam": return cam
    case "lid": return lid
    default: return mot
    }
  }
  var failing: [String] { Health.keys.filter { !self[$0] } }
}

/// One line of the timeline: `e` is armed, triggered, photo, siren, back, lift, hushed, calledoff,
/// disarmed, cancelled, warning or paired; `k` says which trigger, place or way out.
struct EventItem: Equatable, Codable, Sendable, Identifiable {
  var t: Ms
  var e: String
  var k: String?
  var id: String { "\(t)-\(e)" }
}

struct MacState: Equatable, Sendable {
  var phase: Phase = .idle
  var since: Ms = 0
  var armEnd: Ms?
  var lastEnd: Ms?
  var place: Place = .cafe
  var note = ""
  var vol = 80
  var test = false
  var camera = true
  var push = false
  var trigger: Trigger?
  var at: Ms?
  var siren = false
  var stage: Stage?
  var softEnd: Ms?
  var carried = false
  var bumps = 0
  var mac: MacInfo?
  var health = Health()
  var events: [EventItem] = []
  /// Newer than 2 Macs: set when the Mac says hello with v3.
  var v = 2

  init() {}

  init(json j: [String: Any]) {
    func int(_ k: String) -> Int? { (j[k] as? NSNumber)?.intValue }
    func ms(_ k: String) -> Ms? { (j[k] as? NSNumber).map { $0.int64Value } }
    func bool(_ k: String) -> Bool? { (j[k] as? NSNumber)?.boolValue }
    v = int("v") ?? 2
    phase = (j["phase"] as? String).flatMap(Phase.init(rawValue:)) ?? .idle
    since = ms("since") ?? 0
    armEnd = ms("armEnd").flatMap { $0 > 0 ? $0 : nil }
    lastEnd = ms("lastEnd").flatMap { $0 > 0 ? $0 : nil }
    place = (j["place"] as? String).flatMap(Place.init(rawValue:)) ?? .cafe
    note = j["note"] as? String ?? ""
    vol = int("vol") ?? 80
    test = bool("test") ?? false
    camera = bool("camera") ?? true
    push = bool("push") ?? false
    trigger = (j["trigger"] as? String).flatMap(Trigger.init(rawValue:))
    at = ms("at").flatMap { $0 > 0 ? $0 : nil }
    siren = bool("siren") ?? false
    stage = (j["stage"] as? String).flatMap(Stage.init(rawValue:))
    softEnd = ms("softEnd").flatMap { $0 > 0 ? $0 : nil }
    carried = bool("carried") ?? false
    bumps = int("bumps") ?? 0
    if let m = j["mac"] as? [String: Any] {
      mac = MacInfo(
        name: m["name"] as? String ?? "", model: m["model"] as? String ?? "",
        batt: (m["batt"] as? NSNumber)?.intValue ?? 0, chg: (m["chg"] as? NSNumber)?.boolValue ?? false)
    }
    if let h = j["health"] as? [String: Any] {
      health = Health(
        ax: (h["ax"] as? NSNumber)?.boolValue ?? true, cam: (h["cam"] as? NSNumber)?.boolValue ?? true,
        lid: (h["lid"] as? NSNumber)?.boolValue ?? true, mot: (h["mot"] as? NSNumber)?.boolValue ?? true)
    }
    events = (j["events"] as? [[String: Any]] ?? []).compactMap { e in
      guard let t = (e["t"] as? NSNumber)?.int64Value, let name = e["e"] as? String else { return nil }
      return EventItem(t: t, e: name, k: e["k"] as? String)
    }
  }

  /// A v2 Mac says `siren` and nothing about the stage.
  var effectiveStage: Stage? {
    guard phase == .triggered else { return nil }
    return stage ?? (siren ? .siren : .soft)
  }
}

// MARK: - What the relay says

enum Level: String, Codable, Sendable { case owner, pass, status, expired, reset }

/// The first frame of a viewer socket, and `GET /state/<id>`.
struct RelayView: Equatable, Sendable {
  var v = 3
  var level: Level = .owner
  var online = false
  var offlineAt: Ms?
  var state: MacState?
  var photos: [Ms] = []

  init() {}

  init?(data: Data) {
    guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], j["level"] != nil || j["state"] != nil
    else { return nil }
    self.init(json: j)
  }

  init(json j: [String: Any]) {
    v = (j["v"] as? NSNumber)?.intValue ?? 2
    level = (j["level"] as? String).flatMap(Level.init(rawValue:)) ?? .owner
    online = (j["online"] as? NSNumber)?.boolValue ?? false
    offlineAt = (j["offlineAt"] as? NSNumber)?.int64Value
    if let s = j["state"] as? [String: Any] { state = MacState(json: s) }
    photos = (j["photos"] as? [NSNumber] ?? []).map { $0.int64Value }
  }
}

// MARK: - History

struct SessionRecord: Equatable, Codable, Sendable, Identifiable {
  enum Kind: String, Codable, Sendable { case quiet, alarm, test }

  var id: String
  var start: Ms
  var end: Ms
  var place: Place
  var bumps: Int
  var kind: Kind
  var trigger: Trigger?
  var at: Ms?
  var how: String?
  var soft: Int
  var siren: Int
  var photos: [Ms]
  var events: [EventItem]
  var clip: String?

  init(id: String, start: Ms, end: Ms, place: Place, bumps: Int = 0, kind: Kind = .quiet, trigger: Trigger? = nil,
    at: Ms? = nil, how: String? = nil, soft: Int = 0, siren: Int = 0, photos: [Ms] = [], events: [EventItem] = [],
    clip: String? = nil)
  {
    self.id = id; self.start = start; self.end = end; self.place = place; self.bumps = bumps; self.kind = kind
    self.trigger = trigger; self.at = at; self.how = how; self.soft = soft; self.siren = siren
    self.photos = photos; self.events = events; self.clip = clip
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: Keys.self)
    id = (try? c.decode(String.self, forKey: .id)) ?? ""
    start = (try? c.decode(Ms.self, forKey: .start)) ?? 0
    end = (try? c.decode(Ms.self, forKey: .end)) ?? start
    place = (try? c.decode(Place.self, forKey: .place)) ?? .cafe
    bumps = (try? c.decode(Int.self, forKey: .bumps)) ?? 0
    kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .quiet
    trigger = try? c.decode(Trigger.self, forKey: .trigger)
    at = try? c.decode(Ms.self, forKey: .at)
    how = try? c.decode(String.self, forKey: .how)
    soft = (try? c.decode(Int.self, forKey: .soft)) ?? 0
    siren = (try? c.decode(Int.self, forKey: .siren)) ?? 0
    photos = (try? c.decode([Ms].self, forKey: .photos)) ?? []
    events = (try? c.decode([EventItem].self, forKey: .events)) ?? []
    clip = try? c.decode(String.self, forKey: .clip)
  }
  private enum Keys: String, CodingKey {
    case id, start, end, place, bumps, kind, trigger, at, how, soft, siren, photos, events, clip
  }

  var isAlarm: Bool { kind == .alarm }
  var duration: Ms { max(0, end - start) }
}

// MARK: - Commands, phone to Mac

enum Command: Sendable, Equatable {
  case start(place: Place?, note: String?, test: Bool?)
  case stop
  case hush
  case disarm
  case set(place: Place?, note: String?, vol: Int?, test: Bool?)
  case reset

  var kind: String {
    switch self {
    case .start: return "start"
    case .stop: return "stop"
    case .hush: return "hush"
    case .disarm: return "disarm"
    case .set: return "set"
    case .reset: return "reset"
    }
  }

  func body(id: String) -> [String: Any] {
    var b: [String: Any] = ["id": id, "k": kind]
    switch self {
    case .start(let place, let note, let test):
      if let place { b["place"] = place.rawValue }
      if let note { b["note"] = note }
      if let test { b["test"] = test }
    case .disarm:
      b["by"] = "face"
    case .set(let place, let note, let vol, let test):
      if let place { b["place"] = place.rawValue }
      if let note { b["note"] = note }
      if let vol { b["vol"] = vol }
      if let test { b["test"] = test }
    default: break
    }
    return b
  }
}

enum CommandResult: Equatable, Sendable {
  /// The Mac did it.
  case done
  /// The Mac is offline; the relay will hand it over when it is back.
  case queued
  /// The Mac said no (`not-ready`, `busy`, `locked`) or the network did (`net`).
  case failed(String)
}

/// A Mac this phone has been paired with.
struct PairedMac: Codable, Equatable, Sendable, Identifiable {
  var id: String
  var token: String
  var host: String
  var name: String
  var model: String
  /// The name the owner gave it on the phone, if any.
  var custom: String?
  var added: Ms

  var displayName: String { (custom?.isEmpty == false ? custom : nil) ?? name }
}

struct Claimed: Equatable, Sendable {
  var id: String
  var token: String
  var name: String
  var model: String
  var host: String
}

enum RelayDefaults {
  /// What a new pairing uses. A pairing keeps the host it was made with, and the relay's old
  /// workers.dev name reaches the same rooms, so changing this never breaks one.
  static let host = "api.backin5.app"
  /// The website: the support page, the privacy policy and terms, and the Mac download.
  static let site = "backin5.app"
}
