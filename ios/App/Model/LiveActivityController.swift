import ActivityKit
import Foundation
import WidgetKit

/// Keeps one Live Activity per Mac that has something to say (arming, guarding, an alarm) and hands the relay
/// the tokens it needs to update it when the app is asleep.
@MainActor
final class LiveActivityController {
  unowned let store: AppStore
  private var running: [String: Activity<BRBActivityAttributes>] = [:]
  private var watching: [String: [Task<Void, Never>]] = [:]
  private var started = false

  init(store: AppStore) { self.store = store }

  private var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

  /// Picks up activities the system started for us (push-to-start) and reports the push-to-start token.
  func start() {
    guard !started else { return }
    started = true
    for activity in Activity<BRBActivityAttributes>.activities { adopt(activity) }
    Task { [weak self] in
      for await activity in Activity<BRBActivityAttributes>.activityUpdates {
        self?.adopt(activity)
      }
    }
    if #available(iOS 17.2, *) {
      Task { [weak self] in
        for await data in Activity<BRBActivityAttributes>.pushToStartTokenUpdates {
          guard let self else { return }
          self.store.pushToStartToken = data.hex
          self.store.pushRegistrar.registerAll()
        }
      }
    }
  }

  /// Called whenever a Mac's snapshot changes.
  func update(for mac: MacModel) {
    guard enabled else { return }
    guard let state = mac.snapshot.activityState else {
      end(mac.id)
      return
    }
    let content = ActivityContent(state: state, staleDate: nil)
    if let activity = running[mac.id] {
      Task { await activity.update(content) }
      return
    }
    // The system may already be showing one it started itself.
    if let existing = Activity<BRBActivityAttributes>.activities.first(where: { $0.attributes.macId == mac.id }) {
      adopt(existing)
      Task { await existing.update(content) }
      return
    }
    guard store.notif == .allowed || state.look != "armed" else { return }
    do {
      let activity = try Activity.request(
        attributes: BRBActivityAttributes(macId: mac.id, macName: mac.name), content: content, pushType: .token)
      adopt(activity)
    } catch {
      // Too many activities, or the owner turned them off: the notification still tells them.
    }
  }

  func end(_ id: String) {
    guard let activity = running[id] else { return }
    running[id] = nil
    watching[id]?.forEach { $0.cancel() }
    watching[id] = nil
    store.liveActivityTokens[id] = nil
    if let mac = store.mac(id) { store.pushRegistrar.register(mac) }
    Task { await activity.end(nil, dismissalPolicy: .immediate) }
  }

  func endAll() {
    for id in Array(running.keys) { end(id) }
  }

  private func adopt(_ activity: Activity<BRBActivityAttributes>) {
    let id = activity.attributes.macId
    running[id] = activity
    watching[id]?.forEach { $0.cancel() }
    let tokens = Task { [weak self] in
      for await data in activity.pushTokenUpdates {
        guard let self else { return }
        self.store.liveActivityTokens[id] = data.hex
        if let mac = self.store.mac(id) { self.store.pushRegistrar.register(mac) }
      }
    }
    let states = Task { [weak self] in
      for await state in activity.activityStateUpdates {
        guard let self else { return }
        if state == .ended || state == .dismissed {
          if self.running[id]?.id == activity.id {
            self.running[id] = nil
            self.store.liveActivityTokens[id] = nil
            if let mac = self.store.mac(id) { self.store.pushRegistrar.register(mac) }
          }
          return
        }
      }
    }
    watching[id] = [tokens, states]
  }
}

extension Data {
  var hex: String { map { String(format: "%02x", $0) }.joined() }
}
