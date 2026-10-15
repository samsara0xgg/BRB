import SwiftUI
import WidgetKit

/// What a widget draws: every paired Mac as the relay said it a moment ago.
struct BRBWidgetEntry: TimelineEntry {
  let date: Date
  let macs: [MacSnapshot]
  /// When the relay was asked.
  let fetched: Ms
  /// The newest session of the focus Mac, when there is only one Mac (the medium widget shows it).
  var latest: SessionRecord? = nil
  /// Widgets are a BRB Pro feature and Pro isn't unlocked.
  var locked: Bool = false

  var focus: MacSnapshot? { BRBFocus.pick(macs) }
  var others: [MacSnapshot] { BRBFocus.others(of: focus, in: macs) }

  /// The relay couldn't be reached and what we show is older than 20 minutes.
  var isStale: Bool {
    guard let f = focus, f.fetched > 0 else { return false }
    return fetched - f.fetched > 20 * 60_000
  }

  /// When to ask again: 15 minutes, 5 while a Mac is guarding, and right after a countdown ends.
  var nextRefresh: Date {
    let busy = macs.contains(where: { $0.look.isGuarding || $0.look == .arming || $0.look.isAlarm })
    var next = date.addingTimeInterval(busy ? 5 * 60 : 15 * 60)
    for m in macs {
      if m.look == .arming, let end = m.state.armEnd {
        next = Swift.min(next, Swift.max(end.date.addingTimeInterval(2), date.addingTimeInterval(20)))
      }
      if m.look == .warn, let end = m.state.softEnd {
        next = Swift.min(next, Swift.max(end.date.addingTimeInterval(2), date.addingTimeInterval(20)))
      }
    }
    return next
  }

  static func load(wantsHistory: Bool) async -> BRBWidgetEntry {
    let macs = await BRBLoader.snapshots(timeout: 6)
    var entry = BRBWidgetEntry(date: Date(), macs: macs, fetched: nowMs(), latest: nil, locked: !BRBGate.unlocked)
    if wantsHistory, entry.locked == false, let focus = entry.focus, entry.others.isEmpty,
      let mac = Library.macs().first(where: { $0.id == focus.id })
    {
      entry.latest = await BRBLoader.latestSession(of: mac, timeout: 6)
    }
    return entry
  }
}

// MARK: - Samples, for the gallery and while loading

extension BRBWidgetEntry {
  /// A guarded MacBook, so the gallery and the placeholder show what the widget looks like.
  static func sample(now: Date = Date()) -> BRBWidgetEntry {
    let t0 = now.ms
    let info: [String: Any] = ["name": "MacBook Pro", "model": "MacBook Pro 14″", "batt": 82, "chg": false]
    let guarded: [String: Any] = [
      "phase": "armed", "since": t0 - 12 * 60_000, "place": "cafe", "bumps": 2, "mac": info,
    ]
    let idle: [String: Any] = ["phase": "idle", "lastEnd": t0 - 3 * 3_600_000, "place": "library", "mac": info]
    func snap(_ id: String, _ name: String, _ state: [String: Any]) -> MacSnapshot {
      let view = RelayView(json: ["v": 3, "level": "owner", "online": true, "state": state])
      return MacSnapshot(id: id, name: name, model: "MacBook Pro", view: view, lastSeen: t0, fetched: t0)
    }
    let session = SessionRecord(
      id: "sample", start: t0 - 5 * 3_600_000, end: t0 - 3 * 3_600_000, place: .cafe, bumps: 1, kind: .quiet)
    return BRBWidgetEntry(
      date: now, macs: [snap("sample1", "MacBook Pro", guarded), snap("sample2", "Mac mini", idle)], fetched: t0,
      latest: session, locked: false)
  }
}

// MARK: - Provider

struct BRBWidgetProvider: TimelineProvider {
  typealias Entry = BRBWidgetEntry

  func placeholder(in context: Context) -> BRBWidgetEntry {
    BRBWidgetEntry.sample()
  }

  func getSnapshot(in context: Context, completion: @escaping (BRBWidgetEntry) -> Void) {
    if context.isPreview {
      completion(BRBWidgetEntry.sample())
      return
    }
    let wantsHistory = context.family == .systemMedium
    Task {
      let entry = await BRBWidgetEntry.load(wantsHistory: wantsHistory)
      completion(entry)
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<BRBWidgetEntry>) -> Void) {
    let wantsHistory = context.family == .systemMedium
    Task {
      let entry = await BRBWidgetEntry.load(wantsHistory: wantsHistory)
      completion(Timeline(entries: [entry], policy: .after(entry.nextRefresh)))
    }
  }
}
