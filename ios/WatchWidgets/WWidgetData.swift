import Foundation
import WidgetKit

/// One moment of the complication: the Mac it follows and what it last said.
struct WWidgetEntry: TimelineEntry {
  let date: Date
  /// BRB Pro is unlocked, so the Watch shows Macs at all.
  let pro: Bool
  /// The Mac the complication follows: alarm first, then arming, then guarding, else the first.
  let snapshot: MacSnapshot?

  static func sample() -> WWidgetEntry {
    var state = MacState()
    state.phase = .armed
    state.since = nowMs() - 600_000
    var view = RelayView()
    view.online = true
    view.state = state
    let snap = MacSnapshot(id: "sample", name: "MacBook", model: "", view: view, lastSeen: nowMs())
    return WWidgetEntry(date: Date(), pro: true, snapshot: snap)
  }
}

/// Finds the Macs and asks the relay for each one's state. A complication cannot hold a socket.
enum WWidgetLoader {
  static func load() async -> WWidgetEntry {
    let pro = Prefs.pro
    let macs = Library.macs()
    guard pro, !macs.isEmpty else { return WWidgetEntry(date: Date(), pro: pro, snapshot: nil) }

    // Ask every Mac at once; a Mac that does not answer keeps what the Watch app cached.
    let views: [Int: RelayView] = await withTaskGroup(of: (Int, RelayView?).self) { group in
      for (i, mac) in macs.enumerated() {
        group.addTask {
          let view = try? await RelayAPI(mac).view()
          return (i, view)
        }
      }
      var out: [Int: RelayView] = [:]
      for await (i, view) in group {
        if let view { out[i] = view }
      }
      return out
    }

    var snaps: [MacSnapshot] = []
    for (i, mac) in macs.enumerated() {
      if let view = views[i] {
        snaps.append(MacSnapshot(paired: mac, view: view, lastSeen: nowMs()))
      } else {
        snaps.append(Library.cached(mac))
      }
    }
    return WWidgetEntry(date: Date(), pro: pro, snapshot: focus(of: snaps))
  }

  /// Alarm, then arming, then guarding, else the first Mac.
  static func focus(of snaps: [MacSnapshot]) -> MacSnapshot? {
    var best: MacSnapshot?
    var bestRank = 99
    for snap in snaps {
      let r = rank(snap)
      if r < bestRank {
        best = snap
        bestRank = r
      }
    }
    return best
  }

  private static func rank(_ snap: MacSnapshot) -> Int {
    switch snap.state.phase {
    case .triggered: return 0
    case .arming: return 1
    case .armed: return 2
    case .idle: return 3
    }
  }
}

struct WWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> WWidgetEntry { WWidgetEntry.sample() }

  func getSnapshot(in context: Context, completion: @escaping (WWidgetEntry) -> Void) {
    if context.isPreview {
      completion(WWidgetEntry.sample())
      return
    }
    Task {
      let entry = await WWidgetLoader.load()
      completion(entry)
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WWidgetEntry>) -> Void) {
    Task {
      let entry = await WWidgetLoader.load()
      // Ask again soon while something is going on, every 15 minutes otherwise.
      let busy = entry.snapshot?.look.isAlarm == true || entry.snapshot?.look == .arming
      let next = Date().addingTimeInterval(busy ? 60 : 15 * 60)
      completion(Timeline(entries: [entry], policy: .after(next)))
    }
  }
}
