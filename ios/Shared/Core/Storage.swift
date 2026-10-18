import Foundation

/// What the app shares with its widgets, notification extension and Watch: one app group's defaults.
enum Shared {
  static let group = "group.com.allen.brb"
  static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
}

/// The Macs this phone is paired with, and the last thing each one said. The widgets and the Watch read this
/// when they cannot ask the relay.
enum Library {
  private static let macsKey = "macs"

  static func macs() -> [PairedMac] {
    guard let data = Shared.defaults.data(forKey: macsKey) else { return [] }
    return (try? JSONDecoder().decode([PairedMac].self, from: data)) ?? []
  }

  static func save(_ macs: [PairedMac]) {
    Shared.defaults.set(try? JSONEncoder().encode(macs), forKey: macsKey)
  }

  static func cache(id: String, raw: Data, seen: Ms) {
    Shared.defaults.set(raw, forKey: "view.\(id)")
    Shared.defaults.set(seen, forKey: "seen.\(id)")
  }

  static func cached(_ mac: PairedMac) -> MacSnapshot {
    let d = Shared.defaults
    let view = d.data(forKey: "view.\(mac.id)").flatMap(RelayView.init(data:)) ?? RelayView()
    let seen = Ms((d.object(forKey: "seen.\(mac.id)") as? NSNumber)?.int64Value ?? 0)
    return MacSnapshot(paired: mac, view: view, lastSeen: seen)
  }

  static func forget(id: String) {
    Shared.defaults.removeObject(forKey: "view.\(id)")
    Shared.defaults.removeObject(forKey: "seen.\(id)")
  }
}

/// Settings every part of the app needs to agree on.
enum Prefs {
  private static var d: UserDefaults { Shared.defaults }

  /// Face ID before disarming or stopping.
  static var faceRequired: Bool {
    get { d.object(forKey: "faceReq") as? Bool ?? true }
    set { d.set(newValue, forKey: "faceReq") }
  }
  /// Alarms ring through silent mode and Focus.
  static var critical: Bool {
    get { d.object(forKey: "crit") as? Bool ?? true }
    set { d.set(newValue, forKey: "crit") }
  }
  static var events: [String: Bool] {
    get {
      let stored = d.dictionary(forKey: "events") as? [String: Bool] ?? [:]
      return ["siren": true, "back": true, "disarm": true, "guard": false, "sensor": true].merging(stored) { _, new in new }
    }
    set { d.set(newValue, forKey: "events") }
  }
  /// Cached from the purchase check so the widgets and the Watch can follow without StoreKit.
  static var pro: Bool {
    get { d.bool(forKey: "pro") }
    set { d.set(newValue, forKey: "pro") }
  }
  static var onboarded: Bool {
    get { d.bool(forKey: "onboarded") }
    set { d.set(newValue, forKey: "onboarded") }
  }
  /// Stable per install; the relay keeps one registration per value.
  static var deviceID: String {
    if let s = d.string(forKey: "dev") { return s }
    let s = UUID().uuidString.lowercased()
    d.set(s, forKey: "dev")
    return s
  }
  static var lastNote: String {
    get { d.string(forKey: "lastNote") ?? "" }
    set { d.set(newValue, forKey: "lastNote") }
  }
  static var lastPlace: Place {
    get { Place(rawValue: d.string(forKey: "lastPlace") ?? "") ?? .cafe }
    set { d.set(newValue.rawValue, forKey: "lastPlace") }
  }
}
