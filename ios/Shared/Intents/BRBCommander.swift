import Foundation
import WidgetKit

// MARK: - Pro

enum BRBGate {
  /// Widgets, the Dynamic Island, and stopping, hushing or starting from a distance are free; BRB Pro is cloud
  /// video, 30 days of history and the Apple Watch. Flip this to true to lock the widgets and remote commands
  /// behind `Prefs.pro` (the cached purchase check) again.
  static let enforced = false
  static var unlocked: Bool { !enforced || Prefs.pro }
}

// MARK: - Links into the app

/// The URLs the widgets and the Live Activity open. The app's `onOpenURL` can read them with `parse`.
enum BRBDeepLink {
  enum Destination: Equatable {
    case mac(String)
    case alarm(String)
    case addMac
    case pro
  }

  static func mac(_ id: String) -> URL { make("brb://mac/\(id)") }
  static func alarm(_ id: String) -> URL { make("brb://alarm/\(id)") }
  static var addMac: URL { make("brb://add") }
  static var pro: URL { make("brb://pro") }

  private static func make(_ s: String) -> URL { URL(string: s) ?? URL(string: "brb://open")! }

  static func parse(_ url: URL) -> Destination? {
    guard url.scheme == "brb", let host = url.host else { return nil }
    let id = url.pathComponents.dropFirst().first ?? ""
    switch host {
    case "mac": return id.isEmpty ? nil : .mac(id)
    case "alarm": return id.isEmpty ? nil : .alarm(id)
    case "add": return .addMac
    case "pro": return .pro
    default: return nil
    }
  }
}

// MARK: - Refreshing widgets

enum BRBWidgetRefresh {
  /// Asks WidgetKit to rebuild every widget (and, on iOS 18, every control). Call it whenever a Mac's state changes.
  static func reload() {
    Task { await reloadNow() }
  }

  /// The same, for code that is about to finish and wants the request made before the process sleeps.
  static func reloadNow() async {
    await MainActor.run {
      WidgetCenter.shared.reloadAllTimelines()
      #if os(iOS)
        if #available(iOS 18.0, *) {
          ControlCenter.shared.reloadAllControls()
        }
      #endif
    }
  }
}

// MARK: - Commands

/// Sends commands to a Mac straight from a widget, an intent or a notification action, without the app
/// running, and says in a sentence what happened.
enum BRBCommander {
  enum Outcome: Equatable {
    /// The Mac got it.
    case done
    /// The Mac is offline; the relay holds the command.
    case queued
    case failed(String)
  }

  /// What an intent tells the person: a sentence, and whether the thing worked.
  struct Report: Sendable, Equatable {
    var ok: Bool
    var text: String
  }

  struct Resolved {
    var mac: PairedMac
    var snap: MacSnapshot
  }

  static func commandID() -> String {
    String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
  }

  static func send(_ command: Command, to mac: PairedMac) async -> Outcome {
    let relay = BRBLoader.api(for: mac, timeout: 10)
    do {
      let delivered = try await relay.send(command, id: commandID())
      return delivered ? .done : .queued
    } catch let e as RelayError {
      return .failed(e.why)
    } catch {
      return .failed("net")
    }
  }

  /// Asks the relay for the Mac's state until `done` is true or the tries run out (the Mac needs a moment to answer).
  static func waitFor(_ mac: PairedMac, tries: Int = 3, until done: (MacSnapshot) -> Bool) async -> MacSnapshot {
    var snap = await BRBLoader.snapshot(of: mac, timeout: 4)
    var n = 0
    while !done(snap) && n < tries {
      try? await Task.sleep(nanoseconds: 700_000_000)
      snap = await BRBLoader.snapshot(of: mac, timeout: 4)
      n += 1
    }
    return snap
  }

  /// The Mac named by `macID`, else the one that fits the purpose. nil when none does.
  static func resolve(macID: String?, for purpose: BRBFocus.Purpose) async -> Resolved? {
    let macs = Library.macs()
    if let id = macID, !id.isEmpty {
      guard let mac = macs.first(where: { $0.id == id }) else { return nil }
      let snap = await BRBLoader.snapshot(of: mac, timeout: 5)
      return Resolved(mac: mac, snap: snap)
    }
    let snaps = await BRBLoader.snapshots(timeout: 5)
    guard let snap = BRBFocus.target(snaps, for: purpose), let mac = macs.first(where: { $0.id == snap.id }) else {
      return nil
    }
    return Resolved(mac: mac, snap: snap)
  }

  private static func knows(_ macID: String?, in macs: [PairedMac]) -> Bool {
    guard let id = macID, !id.isEmpty else { return true }
    return macs.contains(where: { $0.id == id })
  }

  private static func fallbackName(_ macID: String?, in macs: [PairedMac]) -> String {
    (macs.first(where: { $0.id == macID }) ?? macs.first)?.displayName ?? "Back in 5"
  }

  // MARK: start, stop, hush

  static func startGuarding(macID: String?, place: Place?) async -> Report {
    guard BRBGate.unlocked else { return Report(ok: false, text: t("wi_needsPro")) }
    let macs = Library.macs()
    guard !macs.isEmpty, knows(macID, in: macs) else { return Report(ok: false, text: t("wi_noMac")) }
    guard let target = await resolve(macID: macID, for: .start) else {
      return Report(ok: false, text: t("wi_already", fallbackName(macID, in: macs)))
    }
    let name = target.mac.displayName
    if target.snap.state.phase != .idle { return Report(ok: false, text: t("wi_already", name)) }

    let outcome = await send(.start(place: place, note: nil, test: nil), to: target.mac)
    switch outcome {
    case .failed:
      await BRBWidgetRefresh.reloadNow()
      return Report(ok: false, text: t("wi_failed", name))
    case .queued:
      await BRBWidgetRefresh.reloadNow()
      return Report(ok: true, text: t("toastQueued"))
    case .done:
      let after = await waitFor(target.mac) { $0.state.phase != .idle }
      await BRBWidgetRefresh.reloadNow()
      if after.state.phase != .idle { return Report(ok: true, text: t("wi_started", name)) }
      return Report(ok: false, text: t("wi_notStarted", name))
    }
  }

  /// Stops guarding, cancels the countdown, or (with `allowDisarm`) disarms an alarm.
  static func stopGuarding(macID: String?, allowDisarm: Bool = true) async -> Report {
    guard BRBGate.unlocked else { return Report(ok: false, text: t("wi_needsPro")) }
    let macs = Library.macs()
    guard !macs.isEmpty, knows(macID, in: macs) else { return Report(ok: false, text: t("wi_noMac")) }
    guard let target = await resolve(macID: macID, for: .stop) else {
      return Report(ok: false, text: t("wi_notGuarding", fallbackName(macID, in: macs)))
    }
    let name = target.mac.displayName
    let phase = target.snap.state.phase
    if phase == .idle { return Report(ok: false, text: t("wi_notGuarding", name)) }
    if phase == .triggered && !allowDisarm { return Report(ok: false, text: t("btn_openAlarm")) }

    let command: Command = phase == .triggered ? .disarm : .stop
    let outcome = await send(command, to: target.mac)
    switch outcome {
    case .failed:
      await BRBWidgetRefresh.reloadNow()
      return Report(ok: false, text: t("wi_failed", name))
    case .queued:
      await BRBWidgetRefresh.reloadNow()
      return Report(ok: true, text: t("toastQueued"))
    case .done:
      let after = await waitFor(target.mac) { $0.state.phase == .idle }
      await BRBWidgetRefresh.reloadNow()
      if after.state.phase == .idle { return Report(ok: true, text: t("wi_stopped", name)) }
      return Report(ok: false, text: t("wi_unconfirmed", name))
    }
  }

  /// "Stop siren" (or "Don't sound" during the warning). The Mac stays locked and keeps filming.
  static func hushSiren(macID: String?) async -> Report {
    guard BRBGate.unlocked else { return Report(ok: false, text: t("wi_needsPro")) }
    let macs = Library.macs()
    guard !macs.isEmpty, knows(macID, in: macs) else { return Report(ok: false, text: t("wi_noMac")) }
    guard let target = await resolve(macID: macID, for: .hush) else {
      return Report(ok: false, text: t("wi_noAlarm"))
    }
    let name = target.mac.displayName
    let outcome = await send(.hush, to: target.mac)
    switch outcome {
    case .failed:
      await BRBWidgetRefresh.reloadNow()
      return Report(ok: false, text: t("wi_failed", name))
    case .queued:
      await BRBWidgetRefresh.reloadNow()
      return Report(ok: true, text: t("toastQueued"))
    case .done:
      let after = await waitFor(target.mac) { snap in
        let stage = snap.state.effectiveStage
        return stage == nil || stage == .hushed || stage == .back
      }
      await BRBWidgetRefresh.reloadNow()
      let stage = after.state.effectiveStage
      if stage == nil || stage == .hushed || stage == .back { return Report(ok: true, text: t("wi_hushed", name)) }
      return Report(ok: false, text: t("wi_unconfirmed", name))
    }
  }

  // MARK: questions

  /// One sentence per Mac, or per the Mac asked for.
  static func status(macID: String?) async -> Report {
    let macs = Library.macs()
    guard !macs.isEmpty, knows(macID, in: macs) else { return Report(ok: false, text: t("wi_noMac")) }
    let snaps: [MacSnapshot]
    if let id = macID, !id.isEmpty, let mac = macs.first(where: { $0.id == id }) {
      let one = await BRBLoader.snapshot(of: mac, timeout: 5)
      snaps = [one]
    } else {
      snaps = await BRBLoader.snapshots(timeout: 5)
    }
    let lines = snaps.map { spoken($0) }
    return Report(ok: true, text: lines.joined(separator: " "))
  }

  /// "Allen's MacBook: Guarding. On guard 5:00, nobody touched it."
  static func spoken(_ s: MacSnapshot) -> String {
    let now = nowMs()
    let sub = s.subtitle(now: now).replacingOccurrences(of: " · ", with: ", ")
    return t("wi_status", s.name, s.title(now: now), sub)
  }

  /// The newest session of the Mac asked for, or of whichever Mac has the newest one.
  static func latest(macID: String?) async -> Report {
    let all = Library.macs()
    guard !all.isEmpty, knows(macID, in: all) else { return Report(ok: false, text: t("wi_noMac")) }
    let chosen: [PairedMac]
    if let id = macID, !id.isEmpty { chosen = all.filter { $0.id == id } } else { chosen = all }
    var bestMac: PairedMac?
    var best: SessionRecord?
    for mac in chosen {
      guard let record = await BRBLoader.latestSession(of: mac, timeout: 6) else { continue }
      if best == nil || record.end > (best?.end ?? 0) {
        best = record
        bestMac = mac
      }
    }
    guard let mac = bestMac, let record = best else { return Report(ok: true, text: t("wi_noSessions")) }
    return Report(ok: true, text: t("wi_latest", mac.displayName, BRBSessionText.line(record), BRBSessionText.when(record)))
  }
}
