import Foundation
import UIKit

/// A pretend relay with two pretend Macs. It is what App Review sees when no Mac is at hand, what the
/// screenshots are taken from, and a way to try every screen: it plays the same alarm the real Mac does.
@MainActor
final class DemoBackend: Backend {
  let isDemo = true

  /// A scene to start in, by name (`-scene alarm-siren`).
  enum Scene: String {
    case idle, arming, armed, partial, test, warn, siren, back, muted, offline, offlineAlarm, done, empty
  }

  final class Sim {
    let id: String
    var name: String
    var model: String
    var batt: Int
    var chg: Bool
    var online = true
    var offlineAt: Ms?
    var state = MacState()
    var photos: [Ms] = []
    var history: [SessionRecord] = []
    var queue: [Command] = []
    var tasks: [Task<Void, Never>] = []
    var armedAt: Ms = 0
    var sirenOn: Ms?
    var sirenMs: Ms = 0
    var photoEvents: [EventItem] = []

    init(id: String, name: String, model: String, batt: Int, chg: Bool) {
      self.id = id; self.name = name; self.model = model; self.batt = batt; self.chg = chg
    }
  }

  private(set) var sims: [String: Sim] = [:]
  private var models: [String: MacModel] = [:]
  private var frameLoops: [String: Task<Void, Never>] = [:]

  var paired: [PairedMac] {
    [
      PairedMac(id: "demo1", token: "demo", host: "demo", name: isZh ? "Allen 的 MacBook Pro" : "Allen’s MacBook Pro",
        model: "MacBook Pro 14″", custom: nil, added: nowMs() - 86_400_000),
      PairedMac(id: "demo2", token: "demo", host: "demo", name: isZh ? "工作室 MacBook Air" : "Studio MacBook Air",
        model: "MacBook Air 13″", custom: nil, added: nowMs() - 86_400_000 * 3),
    ]
  }

  init(scene: Scene = .idle) {
    let now = nowMs()
    let p = paired
    let a = Sim(id: p[0].id, name: p[0].name, model: p[0].model, batt: 82, chg: false)
    let b = Sim(id: p[1].id, name: p[1].name, model: p[1].model, batt: 54, chg: true)
    b.online = false
    b.offlineAt = now - 47 * 60_000
    sims = [a.id: a, b.id: b]
    seedHistory(a, b, now: now)
    a.state.mac = MacInfo(name: a.name, model: a.model, batt: a.batt, chg: a.chg)
    b.state.mac = MacInfo(name: b.name, model: b.model, batt: b.batt, chg: b.chg)
    a.state.lastEnd = now - 2 * 3_600_000
    b.state.lastEnd = now - 9 * 3_600_000
    a.state.place = .cafe
    b.state.place = .library
    b.state.vol = 60
    apply(scene: scene, to: a)
  }

  // MARK: Backend

  func attach(_ mac: MacModel) {
    models[mac.id] = mac
    guard let sim = sims[mac.id] else { return }
    mac.setLink(.live)
    publish(sim)
  }

  func detach(_ mac: MacModel) { models[mac.id] = nil }

  func refresh(_ mac: MacModel) async { if let sim = sims[mac.id] { publish(sim) } }

  func send(_ command: Command, to mac: MacModel) async -> CommandResult {
    guard let sim = sims[mac.id] else { return .failed("net") }
    if !sim.online {
      switch command {
      case .hush, .disarm, .stop: sim.queue.append(command); mac.queued = true; return .queued
      default: return .failed("net")
      }
    }
    try? await Task.sleep(nanoseconds: 250_000_000)
    return run(command, on: sim)
  }

  func history(of mac: MacModel) async throws -> [SessionRecord] {
    try? await Task.sleep(nanoseconds: 200_000_000)
    return sims[mac.id]?.history ?? []
  }

  func photo(_ ms: Ms, of mac: MacModel) async -> UIImage? {
    guard let sim = sims[mac.id] else { return nil }
    let mode = modeFor(sim, at: ms)
    return DemoArt.image(at: ms, mode: mode, place: sim.state.place)
  }

  func deleteSession(_ id: String, of mac: MacModel) async throws { sims[mac.id]?.history.removeAll { $0.id == id } }
  func deleteMedia(of mac: MacModel) async throws {}

  func claim(_ code: PairingCode, device: String) async throws -> Claimed {
    try? await Task.sleep(nanoseconds: 900_000_000)
    let p = paired[0]
    return Claimed(id: p.id, token: p.token, name: p.name, model: p.model, host: p.host)
  }

  func register(_ reg: DeviceRegistration, for mac: MacModel) async {}
  func unregister(dev: String, for mac: MacModel) async {}
  func testPush(for mac: MacModel) async throws {}

  // MARK: Publishing

  private func view(of sim: Sim) -> RelayView {
    var v = RelayView()
    v.v = 3
    v.level = .owner
    v.online = sim.online
    v.offlineAt = sim.offlineAt
    var s = sim.state
    s.v = 3
    s.mac = MacInfo(name: sim.name, model: sim.model, batt: sim.batt, chg: sim.chg)
    s.events = sim.photoEvents
    v.state = s
    v.photos = sim.photos
    return v
  }

  func publish(_ sim: Sim) {
    guard let mac = models[sim.id] else { return }
    mac.apply(view: view(of: sim))
    updateFrameLoop(for: sim, mac: mac)
  }

  private func updateFrameLoop(for sim: Sim, mac: MacModel) {
    let live = sim.online && sim.state.phase == .triggered && sim.state.health.cam
    if live, frameLoops[sim.id] == nil {
      frameLoops[sim.id] = Task { [weak self, weak mac] in
        var n = 0
        while !Task.isCancelled {
          guard let self, let mac, let sim = self.sims[mac.id], sim.state.phase == .triggered else { break }
          let at = nowMs()
          mac.frame = DemoArt.image(at: at, mode: self.modeFor(sim, at: at), place: sim.state.place, size: CGSize(width: 640, height: 400), stamp: false)
          mac.frameAt = at
          mac.frameCount += 1
          n += 1
          try? await Task.sleep(nanoseconds: 700_000_000)
        }
        self?.frameLoops[sim.id] = nil
      }
    } else if !live {
      frameLoops[sim.id]?.cancel()
      frameLoops[sim.id] = nil
    }
  }

  private func modeFor(_ sim: Sim, at: Ms) -> DemoArt.Mode {
    if sim.state.carried { return .carried }
    if sim.state.stage == .back { return .returned }
    return sim.state.trigger?.kind == .touch ? .touch : .approach
  }

  // MARK: The Mac's side

  private func log(_ sim: Sim, _ e: String, _ k: String? = nil, at: Ms = nowMs()) {
    sim.photoEvents.append(EventItem(t: at, e: e, k: k))
    if sim.photoEvents.count > 40 { sim.photoEvents.removeFirst() }
  }

  private func run(_ command: Command, on sim: Sim) -> CommandResult {
    switch command {
    case .start(let place, let note, let test):
      guard sim.state.phase == .idle else { return .failed("busy") }
      if let place { sim.state.place = place }
      if let note { sim.state.note = note }
      if let test { sim.state.test = test }
      startArming(sim)
    case .stop:
      if sim.state.phase == .arming { cancelArming(sim) } else if sim.state.phase == .armed { endGuard(sim, how: "phone") }
    case .hush: hush(sim)
    case .disarm: disarm(sim, by: "phone")
    case .set(let place, let note, let vol, let test):
      if let place { sim.state.place = place }
      if let note { sim.state.note = note }
      if let vol { sim.state.vol = vol }
      if let test, sim.state.phase == .idle { sim.state.test = test }
      publish(sim)
    case .reset: break
    }
    return .done
  }

  private func startArming(_ sim: Sim) {
    let now = nowMs()
    sim.photoEvents = []
    sim.photos = []
    sim.state.phase = .arming
    sim.state.armEnd = now + 5000
    sim.state.bumps = 0
    publish(sim)
    sim.tasks.append(Task { [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      guard !Task.isCancelled, let self, sim.state.phase == .arming else { return }
      sim.state.phase = .armed
      sim.state.armEnd = nil
      sim.state.since = nowMs()
      self.log(sim, "armed", sim.state.place.rawValue)
      self.publish(sim)
    })
  }

  private func cancelArming(_ sim: Sim) {
    sim.tasks.forEach { $0.cancel() }
    sim.tasks = []
    sim.state.phase = .idle
    sim.state.armEnd = nil
    log(sim, "cancelled")
    publish(sim)
  }

  func endGuard(_ sim: Sim, how: String) {
    let now = nowMs()
    if sim.state.phase == .armed {
      sim.history.insert(
        SessionRecord(id: "\(sim.state.since)", start: sim.state.since, end: now, place: sim.state.place, bumps: sim.state.bumps,
          kind: sim.state.test ? .test : .quiet, how: how, events: sim.photoEvents), at: 0)
    }
    sim.state.phase = .idle
    sim.state.lastEnd = now
    sim.state.stage = nil
    sim.photoEvents = []
    publish(sim)
  }

  /// What the Mac feels. `kind` is the trigger.
  func trigger(_ sim: Sim, _ trigger: Trigger) {
    guard sim.state.phase == .armed else { return }
    let now = nowMs()
    sim.state.phase = .triggered
    sim.state.trigger = trigger
    sim.state.at = now
    sim.state.carried = trigger.kind == .lift
    log(sim, "triggered", trigger.rawValue, at: now)
    if trigger.kind == .touch {
      sim.state.stage = .soft
      sim.state.softEnd = now + 10_000
      sim.tasks.append(Task { [weak self] in
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        guard !Task.isCancelled, let self, sim.state.stage == .soft else { return }
        self.startSiren(sim)
        self.publish(sim)
      })
    } else {
      startSiren(sim)
    }
    capturePhoto(sim)
    publish(sim)
    sim.tasks.append(Task { [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard !Task.isCancelled, let self, sim.state.phase == .triggered else { return }
      self.capturePhoto(sim)
      self.publish(sim)
    })
  }

  private func startSiren(_ sim: Sim) {
    let now = nowMs()
    sim.state.stage = .siren
    sim.state.siren = true
    sim.state.softEnd = nil
    sim.sirenOn = now
    log(sim, "siren", at: now)
  }

  private func stopSiren(_ sim: Sim) {
    if let s = sim.sirenOn { sim.sirenMs += nowMs() - s }
    sim.sirenOn = nil
    sim.state.siren = false
  }

  private func capturePhoto(_ sim: Sim) {
    guard sim.state.health.cam, sim.photos.count < 6 else { return }
    let now = nowMs()
    sim.photos.insert(now, at: 0)
    log(sim, "photo", at: now)
  }

  func putBack(_ sim: Sim) {
    guard sim.state.phase == .triggered, sim.state.carried else { return }
    sim.state.carried = false
    log(sim, "back")
    if sim.state.stage == .siren {
      stopSiren(sim)
      sim.state.stage = .back
    }
    publish(sim)
  }

  func liftAgain(_ sim: Sim) {
    guard sim.state.phase == .triggered, !sim.state.carried else { return }
    sim.state.carried = true
    switch sim.state.stage {
    case .soft:
      log(sim, "lift")
      startSiren(sim)
    case .siren:
      log(sim, "lift")
    default:
      log(sim, "lift")
      startSiren(sim)
    }
    capturePhoto(sim)
    publish(sim)
  }

  private func hush(_ sim: Sim) {
    switch sim.state.stage {
    case .siren:
      stopSiren(sim)
      sim.state.stage = .hushed
      log(sim, "hushed")
    case .soft:
      sim.state.stage = .hushed
      sim.state.softEnd = nil
      log(sim, "calledoff")
    default: return
    }
    publish(sim)
  }

  func disarm(_ sim: Sim, by: String) {
    guard sim.state.phase == .triggered else { return }
    let now = nowMs()
    stopSiren(sim)
    log(sim, "disarmed", by == "phone" ? "phone" : "fingerprint", at: now)
    let record = SessionRecord(
      id: "\(sim.state.since)", start: sim.state.since, end: now, place: sim.state.place, bumps: sim.state.bumps,
      kind: sim.state.test ? .test : .alarm, trigger: sim.state.trigger, at: sim.state.at, how: by, soft: 0,
      siren: Int(sim.sirenMs / 1000), photos: sim.photos.sorted(), events: sim.photoEvents)
    sim.history.insert(record, at: 0)
    sim.tasks.forEach { $0.cancel() }
    sim.tasks = []
    sim.state.phase = .idle
    sim.state.stage = nil
    sim.state.carried = false
    sim.state.trigger = nil
    sim.state.at = nil
    sim.state.lastEnd = now
    sim.sirenMs = 0
    publish(sim)
  }

  func setOffline(_ sim: Sim, _ off: Bool) {
    guard sim.online == !off else { return }
    sim.online = !off
    sim.offlineAt = off ? nowMs() : nil
    if off { log(sim, "warning", "off") }
    if !off {
      let queued = sim.queue
      sim.queue = []
      models[sim.id]?.queued = false
      for c in queued { _ = run(c, on: sim) }
    }
    publish(sim)
  }

  func bump(_ sim: Sim) {
    guard sim.state.phase == .armed else { return }
    if sim.state.place == .library { trigger(sim, .tilted) } else {
      sim.state.bumps += 1
      publish(sim)
    }
  }

  // MARK: Scenes and history

  private func apply(scene: Scene, to sim: Sim) {
    let now = nowMs()
    func armed(since: Ms) {
      sim.state.phase = .armed
      sim.state.since = since
      sim.state.bumps = 1
    }
    switch scene {
    case .idle, .empty: break
    case .arming:
      sim.state.phase = .arming
      sim.state.armEnd = now + 3500
    case .armed: armed(since: now - 25 * 60_000 - 14_000)
    case .partial:
      armed(since: now - 12 * 60_000)
      sim.state.health.cam = false
    case .test:
      armed(since: now - 3 * 60_000)
      sim.state.test = true
    case .warn, .siren, .back, .muted, .offlineAlarm, .done:
      armed(since: now - 40 * 60_000)
      let touch = scene == .warn
      let at = now - (scene == .warn ? 4000 : 52_000)
      sim.state.phase = .triggered
      sim.state.trigger = touch ? .trackpad : .lifted
      sim.state.at = at
      sim.state.carried = scene == .siren || scene == .offlineAlarm
      sim.photoEvents = [EventItem(t: at, e: "triggered", k: sim.state.trigger?.rawValue)]
      sim.photos = [at + 400, at + 3400].filter { $0 < now }.sorted(by: >)
      for p in sim.photos where p != at + 400 { sim.photoEvents.append(EventItem(t: p, e: "photo")) }
      switch scene {
      case .warn:
        sim.state.stage = .soft
        sim.state.softEnd = at + 10_000
      case .siren, .offlineAlarm:
        sim.state.stage = .siren
        sim.state.siren = true
        sim.sirenOn = at + 600
        sim.photoEvents.append(EventItem(t: at + 600, e: "siren"))
      case .back:
        sim.state.stage = .back
        sim.photoEvents.append(contentsOf: [EventItem(t: at + 600, e: "siren"), EventItem(t: at + 24_000, e: "back")])
      case .muted:
        sim.state.stage = .hushed
        sim.photoEvents.append(contentsOf: [EventItem(t: at + 600, e: "siren"), EventItem(t: at + 21_000, e: "hushed")])
      default: break
      }
      if scene == .offlineAlarm {
        sim.online = false
        sim.offlineAt = now - 20_000
      }
      if scene == .done { sim.tasks.append(Task { [weak self] in
        try? await Task.sleep(nanoseconds: 300_000_000)
        self?.disarm(sim, by: "phone")
      }) }
    case .offline:
      sim.online = false
      sim.offlineAt = now - 8 * 60_000
    }
  }

  private func seedHistory(_ a: Sim, _ b: Sim, now: Ms) {
    let H: Ms = 3_600_000, M: Ms = 60_000
    func rec(_ sim: Sim, _ id: String, endAgo: Ms, mins: Ms, place: Place, bumps: Int = 0, kind: SessionRecord.Kind = .quiet,
      how: String = "phone", trigger: Trigger? = nil) -> SessionRecord
    {
      let end = now - endAgo
      return SessionRecord(id: id, start: end - mins * M, end: end, place: place, bumps: bumps, kind: kind, trigger: trigger, how: how)
    }
    var alarm = rec(a, "r3", endAgo: 26 * H, mins: 40, place: .cafe, kind: .alarm, how: "fingerprint", trigger: .lifted)
    let a0 = alarm.end - 150_000
    alarm.at = a0
    alarm.siren = 66
    alarm.photos = [a0 + 500, a0 + 3500, a0 + 41_000]
    alarm.events = [
      EventItem(t: a0, e: "triggered", k: "lifted"), EventItem(t: a0 + 600, e: "siren"), EventItem(t: a0 + 24_000, e: "back"),
      EventItem(t: a0 + 41_000, e: "lift"), EventItem(t: a0 + 41_600, e: "siren"), EventItem(t: a0 + 88_000, e: "back"),
      EventItem(t: a0 + 150_000, e: "disarmed", k: "fingerprint"),
    ]
    a.history = [
      rec(a, "r1", endAgo: 2 * H, mins: 25, place: .cafe, how: "fingerprint"),
      rec(a, "r2", endAgo: 5 * H, mins: 65, place: .library, bumps: 2),
      rec(a, "r0", endAgo: 8 * H, mins: 90, place: .library, bumps: 2, how: "fingerprint"),
      alarm,
      rec(a, "r4", endAgo: 29 * H, mins: 50, place: .cafe, bumps: 1),
      rec(a, "r5", endAgo: 30 * H + 30 * M, mins: 3, place: .cafe, kind: .test),
      rec(a, "r6", endAgo: 50 * H, mins: 45, place: .library),
      rec(a, "r7", endAgo: 54 * H, mins: 25, place: .transit, how: "fingerprint"),
      rec(a, "r8", endAgo: 75 * H, mins: 25, place: .cafe, bumps: 3),
    ]
    b.history = [
      rec(b, "m2a", endAgo: 9 * H, mins: 130, place: .library),
      rec(b, "m2b", endAgo: 31 * H, mins: 45, place: .library, bumps: 1),
    ]
  }
}

extension DemoBackend {
  /// What the "Simulate the Mac" controls did in the prototype: a bump, a touch, a lift, a put back.
  func simulate(_ what: String, mac id: String) {
    guard let sim = sims[id] else { return }
    switch what {
    case "bump": bump(sim)
    case "touch": trigger(sim, .trackpad)
    case "lift": if sim.state.phase == .triggered { liftAgain(sim) } else { trigger(sim, .lifted) }
    case "back": putBack(sim)
    case "finger": if sim.state.phase == .triggered { disarm(sim, by: "fingerprint") } else if sim.state.phase == .armed { endGuard(sim, how: "fingerprint") }
    case "offline": setOffline(sim, sim.online)
    default: break
    }
  }
}
