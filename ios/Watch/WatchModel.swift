import Foundation
import SwiftUI
import UIKit
import WatchKit
import WidgetKit

/// An alarm that just ended, kept for a few seconds so the wrist shows the green "clear" shield.
struct WFinished: Equatable {
  var by: String
  var endedAt: Ms
  var test: Bool

  /// The three ways out the copy knows: Face ID on the phone, a finger on the Mac, the watch.
  var byKey: String {
    switch by {
    case "phone", "face": return "byS_face"
    case "watch": return "byS_watch"
    default: return "byS_touch"
    }
  }
}

/// A line that shows for a moment after a command: it went through, it waits, or it failed.
struct WNotice: Equatable, Identifiable {
  let id = UUID()
  var text: String
  var good: Bool
}

struct WPhoto {
  var ms: Ms
  var image: UIImage
}

struct WFrame {
  var image: UIImage
  var at: Date
}

/// Everything the Watch app knows: which Macs are paired, what each one last said, and the commands in flight.
@MainActor
final class WatchModel: ObservableObject {
  @Published private(set) var macs: [PairedMac] = []
  @Published private(set) var pro = false
  @Published private(set) var snaps: [String: MacSnapshot] = [:]
  /// Macs whose viewer socket is up right now.
  @Published private(set) var live: Set<String> = []
  /// Macs the Watch could not reach the last time it tried.
  @Published private(set) var lost: Set<String> = []
  /// Macs we have heard something about (from the relay or the cache).
  @Published private(set) var known: Set<String> = []
  /// Macs with a command on its way.
  @Published private(set) var busy: Set<String> = []
  @Published private(set) var finished: [String: WFinished] = [:]
  @Published private(set) var photos: [String: WPhoto] = [:]
  @Published private(set) var frames: [String: WFrame] = [:]
  @Published private(set) var notice: WNotice?
  /// The page the vertical pager shows when there is more than one Mac.
  @Published var selected = ""

  private var watchers: [String: RelayWatcher] = [:]
  private var active = false
  private var acks: [String: CommandResult] = [:]
  private var photoLoading: Set<String> = []
  private var poller: Task<Void, Never>?

  init() {
    WatchLink.shared.onChange = { [weak self] in self?.reload() }
    reload()
  }

  // MARK: Reading

  func snapshot(for id: String) -> MacSnapshot {
    if let s = snaps[id] { return s }
    return MacSnapshot(id: id, name: "", model: "")
  }

  /// False until the relay (or the cache) has said anything about this Mac.
  func hasState(_ id: String) -> Bool { known.contains(id) }

  /// The Mac the Watch shows first: alarm, then arming, then guarding, else the first one.
  var focusID: String? {
    var best: String?
    var bestRank = 99
    for mac in macs {
      let r = WatchModel.rank(snaps[mac.id])
      if r < bestRank {
        best = mac.id
        bestRank = r
      }
    }
    return best
  }

  static func rank(_ snap: MacSnapshot?) -> Int {
    guard let snap else { return 3 }
    switch snap.state.phase {
    case .triggered: return 0
    case .arming: return 1
    case .armed: return 2
    case .idle: return 3
    }
  }

  // MARK: Pairing

  /// Reads the Macs and the Pro flag the iPhone sent (saved by `WatchLink`).
  func reload() {
    let paired = Library.macs()
    let ids = Set(paired.map { $0.id })

    for old in macs {
      let kept = paired.first(where: { $0.id == old.id })
      if kept == nil || kept != old {
        detach(old.id)
      }
      if kept == nil {
        snaps[old.id] = nil
        known.remove(old.id)
        photos[old.id] = nil
        frames[old.id] = nil
        finished[old.id] = nil
      }
    }

    macs = paired
    pro = Prefs.pro

    for mac in paired {
      if snaps[mac.id] == nil {
        let cached = Library.cached(mac)
        snaps[mac.id] = cached
        if cached.view.state != nil { known.insert(mac.id) }
      } else if var snap = snaps[mac.id] {
        snap.name = mac.displayName
        snaps[mac.id] = snap
      }
    }

    if !ids.contains(selected) { selected = focusID ?? "" }
    if active && pro {
      attachAll()
      refreshAll()
    } else if !pro {
      detachAll()
    }
    WidgetCenter.shared.reloadAllTimelines()
  }

  // MARK: Scene

  func sceneChanged(_ phase: ScenePhase) {
    switch phase {
    case .active:
      active = true
      attachAll()
      refreshAll()
      startPolling()
    case .background:
      active = false
      detachAll()
      poller?.cancel()
      poller = nil
    default:
      break
    }
  }

  // MARK: Live updates

  private func attachAll() {
    guard pro else { return }
    for mac in macs where watchers[mac.id] == nil { attach(mac) }
  }

  private func detachAll() {
    for id in Array(watchers.keys) { detach(id) }
  }

  private func attach(_ mac: PairedMac) {
    let id = mac.id
    let watcher = RelayWatcher(api: RelayAPI(mac))
    watcher.onEvent = { [weak self] event in self?.handle(event, id: id) }
    watchers[id] = watcher
    watcher.start()
  }

  private func detach(_ id: String) {
    watchers[id]?.stop()
    watchers[id] = nil
    live.remove(id)
  }

  private func handle(_ event: RelayWatcher.Event, id: String) {
    switch event {
    case .connecting:
      break
    case .connected:
      live.insert(id)
      lost.remove(id)
    case .down:
      live.remove(id)
      lost.insert(id)
    case .view(let view, let raw):
      apply(view, raw: raw, id: id)
    case .frame(let data):
      applyFrame(data, id: id)
    case .ack(let cid, let ok, let why):
      if acks.count > 16 { acks.removeAll() }
      acks[cid] = ok ? .done : .failed(why ?? "failed")
    }
  }

  /// Every few seconds, asks for the state of a Mac that has no socket. A Watch that reaches the internet
  /// only through the iPhone may not be able to keep a WebSocket open; this keeps it current anyway.
  private func startPolling() {
    poller?.cancel()
    poller = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        guard let self, !Task.isCancelled else { return }
        self.pollWithoutSocket()
      }
    }
  }

  private func pollWithoutSocket() {
    guard active, pro else { return }
    for mac in macs where !live.contains(mac.id) {
      Task { await self.refresh(mac) }
    }
  }

  /// Asks every Mac's state once, for when the socket is slow or cannot connect.
  func refreshAll() {
    guard pro else { return }
    for mac in macs {
      Task { await self.refresh(mac) }
    }
  }

  private func refresh(_ mac: PairedMac) async {
    do {
      let view = try await RelayAPI(mac).view()
      apply(view, raw: nil, id: mac.id)
    } catch {
      // Keep what we had; the socket or the next poll catches up.
      if !live.contains(mac.id) { lost.insert(mac.id) }
    }
  }

  // MARK: State

  private func apply(_ view: RelayView, raw: Data?, id: String) {
    guard let paired = macs.first(where: { $0.id == id }) else { return }
    let old = snaps[id]
    let now = nowMs()
    let snap = MacSnapshot(paired: paired, view: view, lastSeen: now)
    snaps[id] = snap
    known.insert(id)
    lost.remove(id)
    if let raw { Library.cache(id: id, raw: raw, seen: now) }
    changed(id: id, from: old, to: snap)
  }

  private func changed(id: String, from old: MacSnapshot?, to snap: MacSnapshot) {
    let wasTriggered = old?.state.phase == .triggered
    let isTriggered = snap.state.phase == .triggered

    if isTriggered {
      finished[id] = nil
      let oldStage = old?.state.effectiveStage
      let stage = snap.state.effectiveStage
      if !wasTriggered || oldStage != stage {
        if stage == .soft {
          buzz(.notification)
        } else if stage == .siren {
          buzz(.failure)
        }
      }
      if !wasTriggered { selected = id }
      loadPhoto(for: snap)
    } else {
      photos[id] = nil
      frames[id] = nil
      // An alarm we watched end: show the green shield for a moment.
      if wasTriggered, let old, nowMs() - old.lastSeen < 120_000 {
        let by = snap.state.events.last(where: { $0.e == "disarmed" })?.k ?? "fingerprint"
        let done = WFinished(by: by, endedAt: nowMs(), test: old.state.test)
        finished[id] = done
        buzz(.success)
        clearFinished(id: id, after: 6, matching: done)
      }
    }

    if old?.look != snap.look { WidgetCenter.shared.reloadAllTimelines() }
  }

  private func clearFinished(id: String, after seconds: Double, matching done: WFinished) {
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      if self?.finished[id] == done { self?.finished[id] = nil }
    }
  }

  // MARK: Pictures

  /// Fetches the newest photo of the alarm that is running. They are listed newest first.
  private func loadPhoto(for snap: MacSnapshot) {
    guard let paired = macs.first(where: { $0.id == snap.id }) else { return }
    let at = snap.state.at ?? 0
    guard let ms = snap.view.photos.first(where: { at == 0 || $0 >= at - 3000 }) else { return }
    let key = "\(snap.id)/\(ms)"
    if photos[snap.id]?.ms == ms || photoLoading.contains(key) { return }
    photoLoading.insert(key)
    let id = snap.id
    Task {
      let data = try? await RelayAPI(paired).photo(ms)
      self.photoLoading.remove(key)
      guard let data, let image = UIImage(data: data) else { return }
      if self.snaps[id]?.state.phase == .triggered {
        self.photos[id] = WPhoto(ms: ms, image: image)
      }
    }
  }

  /// The camera frames the Mac streams while an alarm runs. One every second and a half is plenty here.
  private func applyFrame(_ data: Data, id: String) {
    let now = Date()
    if let last = frames[id], now.timeIntervalSince(last.at) < 1.5 { return }
    guard snaps[id]?.state.phase == .triggered, let image = UIImage(data: data) else { return }
    frames[id] = WFrame(image: image, at: now)
  }

  // MARK: Commands

  /// Sends a command to a Mac and says how it went. `done` is the line to show when the Mac did it.
  func send(_ command: Command, to id: String, done: String? = nil) async {
    guard let paired = macs.first(where: { $0.id == id }), !busy.contains(id) else { return }
    busy.insert(id)
    let result = await deliver(command, to: paired)
    busy.remove(id)

    switch result {
    case .done:
      buzz(.success)
      if let done { show(t(done), good: true) }
    case .queued:
      buzz(.retry)
      show(t("toastQueued"), good: false)
    case .failed(let why):
      buzz(.failure)
      show(failText(why), good: false)
    }

    // Without a socket nobody tells us what changed; ask.
    var failed = false
    if case .failed = result { failed = true }
    if !failed && !live.contains(id) {
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      await refresh(paired)
    }
  }

  private func deliver(_ command: Command, to paired: PairedMac) async -> CommandResult {
    let cid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
    do {
      let delivered = try await RelayAPI(paired).send(command, id: cid)
      if !delivered { return .queued }
      // The Mac answers on the socket when we have one open; without it, trust the relay.
      guard live.contains(paired.id) else { return .done }
      return await waitForAck(cid, timeout: 4) ?? .done
    } catch let e as RelayError {
      return .failed(e.status == 403 ? "forbidden" : e.why)
    } catch {
      return .failed("net")
    }
  }

  private func waitForAck(_ cid: String, timeout: Double) async -> CommandResult? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if let result = acks.removeValue(forKey: cid) { return result }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return nil
  }

  private func failText(_ why: String) -> String {
    switch why {
    case "net": return t("ww_failNet")
    case "not-ready": return t("ww_failNotReady")
    case "busy": return t("ww_failBusy")
    case "locked": return t("ww_failLocked")
    case "forbidden": return t("ww_failForbidden")
    default: return t("ww_failOther")
    }
  }

  private func show(_ text: String, good: Bool) {
    let n = WNotice(text: text, good: good)
    notice = n
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_800_000_000)
      if self?.notice?.id == n.id { self?.notice = nil }
    }
  }

  // MARK: Haptics

  private func buzz(_ type: WKHapticType) {
    guard active else { return }
    WKInterfaceDevice.current().play(type)
  }
}
