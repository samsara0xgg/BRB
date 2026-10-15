import Observation
import SwiftUI
import UIKit

enum Link: Equatable { case connecting, live, down }

enum Loadable: Equatable { case idle, loading, loaded, failed }

/// What the alarm page keeps showing after the Mac was disarmed: the summary, until the owner taps Done.
struct FinishedAlarm: Equatable {
  var trigger: Trigger.Kind
  var test: Bool
  var place: Place
  var at: Ms
  var endedAt: Ms
  /// `phone`, `fingerprint`... as the Mac named the way out.
  var by: String
  var sirenMs: Int
  var photos: [Ms]
  var events: [EventItem]

  /// The three ways out the copy knows: Face ID on the phone, a finger on the Mac, the watch.
  var byKey: String {
    switch by {
    case "phone", "face": return "by_face"
    case "watch": return "by_watch"
    default: return "by_touch"
    }
  }
}

/// One paired Mac as the app sees it: what the relay said last, the picture, the history.
@Observable @MainActor
final class MacModel: Identifiable {
  let id: String
  private(set) var paired: PairedMac
  var snapshot: MacSnapshot
  var link: Link = .connecting
  var frame: UIImage?
  var frameAt: Ms = 0
  var frameCount = 0
  var sessions: [SessionRecord] = []
  var sessionsState: Loadable = .idle
  var finished: FinishedAlarm?
  /// A command waits in the relay's queue for this Mac.
  var queued = false
  /// The phone has no network at all.
  var phoneOffline = false
  /// The Mac made a new link: this phone's token no longer works.
  private(set) var linkEnded = false

  init(paired: PairedMac, snapshot: MacSnapshot? = nil) {
    self.id = paired.id
    self.paired = paired
    self.snapshot = snapshot ?? Library.cached(paired)
  }

  var name: String { paired.displayName }
  var model: String { snapshot.state.mac?.model.isEmpty == false ? snapshot.state.mac!.model : paired.model }
  var state: MacState { snapshot.state }
  var look: Look { snapshot.look }
  var online: Bool { snapshot.online }
  var photos: [Ms] { snapshot.view.photos }
  var alarmActive: Bool { state.phase == .triggered }

  func rename(_ new: String) {
    paired.custom = new.trimmingCharacters(in: .whitespaces).isEmpty ? nil : new
    snapshot.name = paired.displayName
  }

  /// Everything about this Mac that the relay sent, in one place.
  func apply(view: RelayView, raw: Data? = nil, at now: Ms = nowMs()) {
    let old = snapshot.view.state
    let oldLook: Look? = snapshot.view.state == nil ? nil : snapshot.look
    var snap = snapshot
    snap.view = view
    snap.lastSeen = now
    snap.fetched = now
    snap.name = paired.displayName
    if let info = view.state?.mac, !info.name.isEmpty, paired.name != info.name || paired.model != info.model {
      paired.name = info.name
      paired.model = info.model.isEmpty ? paired.model : info.model
      snap.name = paired.displayName
    }
    snapshot = snap
    if let raw { Library.cache(id: id, raw: raw, seen: now) }

    // An alarm that just ended: keep its story for the summary.
    if let old, old.phase == .triggered, let new = view.state, new.phase != .triggered {
      finished = FinishedAlarm(
        trigger: old.trigger?.kind ?? .lift, test: old.test, place: old.place, at: old.at ?? old.since, endedAt: now,
        by: new.events.last(where: { $0.e == "disarmed" })?.k ?? "fingerprint",
        sirenMs: EventText.sirenMs(events: old.events + new.events.filter { e in !old.events.contains(e) }, endedAt: now),
        photos: photosOfAlarm(from: old.at ?? old.since, in: snapshot.view.photos), events: old.events)
    }
    if view.state?.phase == .triggered { finished = nil }
    if view.level == .reset || view.level == .expired {
      if !linkEnded { AppStore.shared.show(t("err_forbidden"), "exclamationmark.triangle") }
      linkEnded = true
    } else {
      linkEnded = false
    }
    AppStore.shared.macChanged(self, from: oldLook)
  }

  func apply(frame data: Data, at now: Ms = nowMs()) {
    guard let image = UIImage(data: data) else { return }
    frame = image
    frameAt = now
    frameCount += 1
  }

  /// Photos of the alarm that began at `at`, oldest first.
  func photosOfAlarm(from at: Ms, in all: [Ms]) -> [Ms] {
    all.filter { $0 >= at - 3000 }.sorted()
  }

  /// The photos of the alarm that is running, newest first as the relay lists them.
  var alarmPhotos: [Ms] {
    guard let at = state.at else { return [] }
    return photos.filter { $0 >= at - 3000 }
  }

  func setLink(_ l: Link) { link = l }
}

enum EventText {
  /// How long the siren actually sounded, from the events: from each `siren` to the next `back`, `hushed`,
  /// `calledoff` or `disarmed` (or the end).
  static func sirenMs(events: [EventItem], endedAt: Ms) -> Int {
    var total: Ms = 0
    var since: Ms?
    for e in events.sorted(by: { $0.t < $1.t }) {
      switch e.e {
      case "siren": if since == nil { since = e.t }
      case "back", "hushed", "calledoff", "disarmed", "cancelled":
        if let s = since { total += e.t - s; since = nil }
      default: break
      }
    }
    if let s = since { total += max(0, endedAt - s) }
    return Int(total)
  }

  /// "Picked up", "Siren on"... for one event, and the tone of its dot.
  enum Tone { case plain, hot, ok, clear }

  static func text(_ e: EventItem, place: Place? = nil) -> String {
    switch e.e {
    case "armed": return t("ev_start")
    case "triggered":
      switch Trigger(rawValue: e.k ?? "")?.kind ?? .lift {
      case .touch: return t("ev_touch")
      case .nudge: return t("ev_nudge")
      case .lift: return t("ev_lift")
      }
    case "lift": return t("ev_relift")
    case "photo": return t("ev_photo")
    case "bump": return t("ev_bump")
    case "siren": return t("ev_siren")
    case "back": return t("ev_back")
    case "hushed": return t("ev_hush")
    case "calledoff": return t("ev_calloff")
    case "disarmed":
      switch e.k ?? "" {
      case "phone": return t("ev_face")
      case "watch": return t("ev_watch")
      default: return t("ev_touchid")
      }
    case "cancelled": return t("ev_end")
    case "warning": return t("p_sensor")
    case "paired": return t("ev_on")
    default: return e.e
    }
  }

  static func tone(_ e: EventItem) -> Tone {
    switch e.e {
    case "triggered", "siren", "lift": return .hot
    case "back": return .ok
    case "disarmed": return .clear
    default: return .plain
    }
  }
}
