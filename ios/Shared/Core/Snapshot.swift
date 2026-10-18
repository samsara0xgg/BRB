import Foundation

/// How a Mac looks at a glance. The shield, the card and the widgets all follow this.
enum Look: String, Sendable, CaseIterable {
  case idle, arming, armed, partial, test, warn, alarm, offline

  var isAlarm: Bool { self == .alarm || self == .warn }
  var isGuarding: Bool { self == .armed || self == .partial || self == .test }
}

/// Where an alarm stands, for the alarm page. `done` is what the phone shows after the Mac was disarmed.
enum AlarmPhase: String, Sendable {
  case warn, siren, returned, muted, done
}

/// A Mac and the last thing the relay told us about it. A plain value, so the app, the widgets and the
/// Watch all read it the same way.
struct MacSnapshot: Equatable, Sendable, Identifiable {
  var id: String
  var name: String
  var model: String
  var view: RelayView
  /// When we last heard from the Mac (a frame, a state, a photo), for "last seen".
  var lastSeen: Ms
  /// When this snapshot was taken, so a widget can say how stale it is.
  var fetched: Ms

  init(id: String, name: String, model: String, view: RelayView = RelayView(), lastSeen: Ms = 0, fetched: Ms = nowMs()) {
    self.id = id; self.name = name; self.model = model; self.view = view; self.lastSeen = lastSeen; self.fetched = fetched
  }

  var state: MacState { view.state ?? MacState() }
  var online: Bool { view.online }

  var look: Look {
    let s = state
    if s.phase == .triggered { return s.effectiveStage == .soft ? .warn : .alarm }
    if !view.online { return .offline }
    switch s.phase {
    case .arming: return .arming
    case .armed:
      if s.test { return .test }
      return !s.health.ax || !s.health.cam || !s.health.mot || !s.camera ? .partial : .armed
    default: return .idle
    }
  }

  var alarmPhase: AlarmPhase? {
    switch state.effectiveStage {
    case .soft: return .warn
    case .siren: return .siren
    case .back: return .returned
    case .hushed: return .muted
    case nil: return nil
    }
  }

  var trigger: Trigger.Kind { state.trigger?.kind ?? .lift }

  /// The owner called a warning off rather than silencing a siren.
  var calledOff: Bool {
    for e in state.events.reversed() where e.e == "calledoff" || e.e == "hushed" { return e.e == "calledoff" }
    return false
  }

  /// When we last knew the Mac was there.
  var lastSeenTime: Ms { view.offlineAt ?? (lastSeen > 0 ? lastSeen : fetched) }

  // MARK: Text

  func secsLeft(until ts: Ms?, now: Ms) -> Int {
    guard let ts else { return 1 }
    return max(1, Int((Double(ts - now) / 1000).rounded(.up)))
  }

  /// The big word on the card and the detail page.
  func title(now: Ms = nowMs()) -> String {
    let s = state
    switch look {
    case .idle: return t("st_idle")
    case .arming: return t("st_arming", secsLeft(until: s.armEnd, now: now))
    case .armed: return t("st_armed")
    case .partial: return t("st_partial")
    case .test: return t("st_test")
    case .offline: return t("st_offline")
    case .alarm, .warn: return trigger.title
    }
  }

  /// The line under it.
  func subtitle(now: Ms = nowMs()) -> String {
    let s = state
    switch look {
    case .idle:
      guard let end = s.lastEnd else { return t("sub_never") }
      return t("sub_idle", Fmt.ago(end, now: now))
    case .arming: return t("sub_arming")
    case .armed:
      let d = t("gFor", Fmt.elapsed(now - s.since))
      return s.bumps > 0 ? t("sub_armed", d, tn("n_bumps", s.bumps)) : t("sub_armed0", d)
    case .partial:
      return t(!s.health.cam || !s.camera ? "sub_partial_cam" : !s.health.mot ? "sub_partial_mot" : "sub_partial_ax")
    case .test: return t("sub_test", Fmt.elapsed(now - s.since))
    case .offline: return t("sub_offline", Fmt.hm(lastSeenTime))
    case .alarm, .warn:
      if !view.online { return t("sub_alOff", Fmt.hm(lastSeenTime)) }
      switch alarmPhase {
      case .warn: return t("sub_warn", secsLeft(until: s.softEnd, now: now))
      case .siren: return s.test ? t("lb_test") : t("sub_siren", Fmt.elapsed(now - (s.at ?? now)))
      case .returned: return t("sub_returned")
      default: return t(calledOff ? "sub_calledoff" : "sub_muted")
      }
    }
  }

  /// One plain line for a widget or a notification.
  func plain(now: Ms = nowMs()) -> String {
    switch look {
    case .offline: return t("sub_offline", Fmt.hm(lastSeenTime))
    case .arming: return t("la_arm")
    case .alarm, .warn: return trigger.title
    case .armed, .partial: return t("st_armed")
    default: return title(now: now)
    }
  }
}

extension MacSnapshot {
  /// A Mac with a view made from the paired record, before anything arrived.
  init(paired: PairedMac, view: RelayView = RelayView(), lastSeen: Ms = 0) {
    self.init(id: paired.id, name: paired.displayName, model: paired.model, view: view, lastSeen: lastSeen)
  }
}
