import Foundation

/// How the widgets, the Live Activity buttons and the intents ask the relay: short timeouts, and the last
/// thing the app cached when the relay can't be reached.
enum BRBLoader {
  /// A session that gives up after `timeout` seconds in all, so a timeline never waits for a dead network.
  static func session(timeout: TimeInterval) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = timeout
    config.timeoutIntervalForResource = timeout + 2
    config.waitsForConnectivity = false
    return URLSession(configuration: config)
  }

  static func api(for mac: PairedMac, timeout: TimeInterval) -> RelayAPI {
    RelayAPI(host: mac.host, id: mac.id, token: mac.token, session: session(timeout: timeout))
  }

  /// The Mac as the relay says it now (and cached for the app), or as it was last seen.
  static func snapshot(of mac: PairedMac, timeout: TimeInterval = 6) async -> MacSnapshot {
    let relay = api(for: mac, timeout: timeout)
    do {
      let (data, status) = try await relay.request("GET", "/state/\(mac.id)", timeout: timeout)
      if (200..<300).contains(status), let view = RelayView(data: data) {
        let now = nowMs()
        Library.cache(id: mac.id, raw: data, seen: now)
        return MacSnapshot(paired: mac, view: view, lastSeen: now)
      }
    } catch {
      // Offline or slow: fall through to what we have.
    }
    return cached(mac)
  }

  /// The last cached view of a Mac. `fetched` is when that was, so a widget can say it is out of date.
  static func cached(_ mac: PairedMac) -> MacSnapshot {
    var snap = Library.cached(mac)
    snap.fetched = snap.lastSeen
    return snap
  }

  /// Every paired Mac, asked at the same time, in the order they were paired.
  static func snapshots(timeout: TimeInterval = 6) async -> [MacSnapshot] {
    let macs = Library.macs()
    return await withTaskGroup(of: (Int, MacSnapshot).self) { group in
      for (index, mac) in macs.enumerated() {
        group.addTask {
          let snap = await BRBLoader.snapshot(of: mac, timeout: timeout)
          return (index, snap)
        }
      }
      var found: [(Int, MacSnapshot)] = []
      for await item in group { found.append(item) }
      return found.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
  }

  // MARK: latest session

  private static func latestKey(_ id: String) -> String { "wg.latest.\(id)" }

  static func cachedLatest(_ id: String) -> SessionRecord? {
    guard let data = Shared.defaults.data(forKey: latestKey(id)) else { return nil }
    return try? JSONDecoder().decode(SessionRecord.self, from: data)
  }

  /// The newest session in the Mac's history, or the one cached last time if the relay doesn't answer.
  static func latestSession(of mac: PairedMac, timeout: TimeInterval = 6) async -> SessionRecord? {
    do {
      let list = try await api(for: mac, timeout: timeout).history()
      if let first = list.first, let data = try? JSONEncoder().encode(first) {
        Shared.defaults.set(data, forKey: latestKey(mac.id))
      } else {
        Shared.defaults.removeObject(forKey: latestKey(mac.id))
      }
      return list.first
    } catch {
      return cachedLatest(mac.id)
    }
  }
}

/// The one-line story of a session, the way the History list tells it.
enum BRBSessionText {
  static func line(_ r: SessionRecord) -> String {
    switch r.kind {
    case .alarm:
      let phrase = (r.trigger?.kind ?? Trigger.Kind.lift).phrase
      return t("rl_alarm", phrase, how(r.how))
    case .test:
      return t("rl_test")
    case .quiet:
      let length = Fmt.duration(r.duration)
      if r.bumps > 0 { return t("rl_bumps", length, tn("n_bumps", r.bumps)) }
      return t("rl_quiet", length)
    }
  }

  /// "disarmed with Touch ID" and its two siblings. The Mac names the way out in its own words.
  static func how(_ raw: String?) -> String {
    let h = raw ?? ""
    if h == "phone" || h == "face" { return t("how_face") }
    if h == "watch" { return t("how_watch") }
    return t("how_touch")
  }

  /// "Today, 14:05"
  static func when(_ r: SessionRecord) -> String {
    Fmt.dayLabel(r.end) + ", " + Fmt.hm(r.end)
  }
}
