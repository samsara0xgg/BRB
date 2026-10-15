import AppKit
import CryptoKit
import Foundation
import IOKit
import IOKit.ps

/// What the phone page and the iPhone app show, sent to the relay whenever it changes. The fields
/// are the ones in relay/PROTOCOL.md; the relay drops anything else.
struct LiveState: Encodable, Equatable {
  struct Event: Encodable, Equatable {
    let t: Int64      // ms since 1970
    let e: String     // armed, triggered, photo, siren, lift, hushed, calledoff, disarmed, cancelled, warning
    let k: String?    // the trigger or the disarm, for the page to name
  }

  /// This Mac, for the iPhone's card. `batt` is nil without a battery.
  struct Mac: Encodable, Equatable {
    var name: String
    var model: String
    var batt: Int?
    var chg: Bool
  }

  /// What works: Accessibility, the camera, the lid rule, the motion sensor. True is fine.
  struct Health: Encodable, Equatable {
    var ax: Bool
    var cam: Bool
    var lid: Bool
    var mot: Bool
  }

  var v = 3
  var phase = "idle"  // idle, arming, armed, triggered
  var since: Int64 = 0
  var armEnd: Int64 = 0  // while arming: when the countdown ends
  var lastEnd: Int64?  // when the previous session ended
  var place = ""
  var note = ""
  var vol = 100
  var push = false
  var test = false
  var camera = false
  var trigger: String?
  var at: Int64?
  var siren = false
  var stage: String?  // while triggered: soft, siren or hushed
  var softEnd: Int64?  // while soft: when it turns into the siren
  var carried = false
  var bumps = 0
  var mac: Mac?
  var health: Health?
  var events: [Event] = []
  var pass: String?

  static func ms(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }
}

/// One finished session, sent once for the iPhone's history.
struct SessionRecord: Encodable {
  let id: String  // when it was armed, in ms, as text
  let start: Int64
  let end: Int64
  let place: String
  let bumps: Int
  let kind: String  // quiet, alarm, test
  let trigger: String?
  let at: Int64?
  let how: String
  let soft: Int
  let siren: Int
  let photos: [Int64]
  let events: [LiveState.Event]
  let clip: String?
}

/// A command from a paired phone, as the relay forwards it: `{"cmd": {...}, "from": "phone"}`.
struct PhoneCommand: Equatable {
  enum Kind: String { case start, stop, hush, disarm, set, reset }

  let id: String
  let kind: Kind
  var place: Place?
  var note: String?
  var vol: Int?
  var test: Bool?
  var by: String?

  /// Nil for what is not a command this Mac knows; the caller answers that with `bad-command`.
  static func decode(_ json: [String: Any]) -> PhoneCommand? {
    guard let id = json["id"] as? String, (1...24).contains(id.count),
          let kind = (json["k"] as? String).flatMap(Kind.init(rawValue:)) else { return nil }
    var command = PhoneCommand(id: id, kind: kind)
    command.place = (json["place"] as? String).flatMap(Place.init(rawValue:))
    command.note = json["note"] as? String
    command.vol = (json["vol"] as? NSNumber).map { max(0, min(100, $0.intValue)) }
    command.test = json["test"] as? Bool
    command.by = json["by"] as? String
    return command
  }
}

/// A pairing code the relay made for this Mac: six digits to type, or `qr` in the link the QR code carries.
struct PairOffer: Equatable {
  let code: String
  let qr: String
  let expires: Date

  var link: String { "https://\(Live.host)/pair/\(qr)" }

  /// "123 456", easier to read off a screen.
  var spaced: String { code.count == 6 ? String(code.prefix(3)) + " " + String(code.suffix(3)) : code }
}

/// This Mac as the iPhone shows it.
enum MacInfo {
  /// "Allen's MacBook Pro", as the Mac calls itself in Sharing.
  static var name: String {
    String((Host.current().localizedName ?? ProcessInfo.processInfo.hostName).prefix(40))
  }

  /// The product name where the registry has one, otherwise the identifier ("Mac14,5").
  static var model: String {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    guard service != 0 else { return "Mac" }
    defer { IOObjectRelease(service) }
    for key in ["product-name", "model"] {
      if let data = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
         let text = String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\0", with: ""), !text.isEmpty {
        return String(text.prefix(40))
      }
    }
    return "Mac"
  }

  /// The internal battery's charge and whether it is charging; nil on a Mac without one.
  static func battery() -> (percent: Int, charging: Bool)? {
    let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
    for source in sources {
      guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
            info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
            let now = info[kIOPSCurrentCapacityKey] as? Int, let full = info[kIOPSMaxCapacityKey] as? Int, full > 0 else { continue }
      return (max(0, min(100, now * 100 / full)), info[kIOPSIsChargingKey] as? Bool ?? false)
    }
    return nil
  }

  /// The Mac card of the state, with the battery as it is now.
  static func card() -> LiveState.Mac {
    let charge = battery()
    return LiveState.Mac(name: name, model: model, batt: charge?.percent, chg: charge?.charging ?? false)
  }
}

/// The phone page and the iPhone app, through the BRB relay (relay/, a Cloudflare Worker). From the
/// countdown on the Mac holds a WebSocket to the relay and keeps it told what is happening; camera
/// frames flow only after a trigger and only while an allowed page is open. Photos of an alarm are
/// kept by the relay for 7 days. With an iPhone paired the socket also stays open between sessions,
/// so the phone sees the Mac and its commands arrive at once.
///
/// Who sees what: the link in the panel carries the owner's token after `#` (never sent in a request
/// line, so never in a server log), and shows everything. The link in an alarm push carries a pass
/// that works only until that alarm is disarmed, because ntfy keeps its messages. Without either,
/// the page shows only whether the Mac is guarded. A paired phone holds the owner's token too.
final class Live {
  /// The author's relay, unless `defaults write com.allen.guard-mode relayHost <host>` names your own.
  static var host: String {
    let own = UserDefaults.standard.string(forKey: "relayHost") ?? ""
    return own.isEmpty ? "guardmode-relay.guardmode-gf1n2.workers.dev" : own
  }

  /// The Mac's secret: it connects as the camera with it.
  static var key: String { stored("liveKey", length: 32) }
  /// The owner's viewing token.
  static var token: String { stored("liveToken", length: 24) }

  static var id: String {
    SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
  }

  static var link: URL { URL(string: "https://\(host)/v/\(id)#\(token)")! }

  /// Posted after `resetLink()`, wherever it was asked for, so the app can move the open connection to the new room.
  static let didReset = Notification.Name("BRBLiveLinkReset")

  /// A new key and token: the old link stops working, and the relay forgets the old room. Every
  /// paired phone held the old token, so none is paired any more.
  static func resetLink() {
    var request = URLRequest(url: URL(string: "https://\(host)/wipe/\(key)")!, timeoutInterval: 15)
    request.httpMethod = "POST"
    URLSession.shared.dataTask(with: request) { _, response, error in
      log("old live room wiped: \(error?.localizedDescription ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")")
    }.resume()
    UserDefaults.standard.removeObject(forKey: "liveKey")
    UserDefaults.standard.removeObject(forKey: "liveToken")
    Prefs.phonePaired = false
    Prefs.phoneName = ""
    NotificationCenter.default.post(name: didReset, object: nil)
    log("live link reset")
  }

  /// Asks the relay for a pairing code. A new one replaces the Mac's previous one; it lives 10
  /// minutes and works once.
  static func pairOffer(_ done: @escaping (Result<PairOffer, GuardError>) -> Void) {
    var request = URLRequest(url: URL(string: "https://\(host)/pair/\(key)")!, timeoutInterval: 15)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": token, "name": MacInfo.name, "model": MacInfo.model])
    URLSession.shared.dataTask(with: request) { data, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
      DispatchQueue.main.async {
        guard status == 200, let code = reply?["code"] as? String, let qr = reply?["qr"] as? String,
              let expires = (reply?["expires"] as? NSNumber)?.doubleValue else {
          let why = error?.localizedDescription ?? "HTTP \(status)"
          log("pairing code not made: \(why)")
          return done(.failure(GuardError(why)))
        }
        done(.success(PairOffer(code: code, qr: qr, expires: Date(timeIntervalSince1970: expires / 1000))))
      }
    }.resume()
  }

  private static func stored(_ name: String, length: Int) -> String {
    if let k = UserDefaults.standard.string(forKey: name) { return k }
    let k = random(length)
    UserDefaults.standard.set(k, forKey: name)
    return k
  }

  static func random(_ n: Int) -> String {
    let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
    return String((0..<n).map { _ in alphabet.randomElement()! })
  }

  private(set) var state = LiveState()
  /// A command arrived from a paired phone. Answer it with `ack`.
  var onCommand: ((PhoneCommand) -> Void)?
  /// A phone claimed the pairing code; the name it gave.
  var onPaired: ((String) -> Void)?
  private var task: URLSessionWebSocketTask?
  private var recorder: Recorder?
  /// What `hello` says this Mac speaks. The relay delivers queued commands and the pairing notice to
  /// a v3 Mac only, so the `live` command, which has no one to hand them to, says 2.
  var helloVersion = 3
  private var running = false  // a session is under way
  private var wanted = false  // the socket stays open between sessions
  private var viewers = 0
  private var sending = false
  private var ping: Timer?
  private var retryDelay = 5.0
  /// Finished sessions the relay has not been told of yet (no connection at the time).
  private var unsent: [String] = []

  init() {
    // A sleeping Mac's socket is dead; the phone should see it online again as soon as it wakes.
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      self?.reconnect()
    }
  }

  /// The link for this alarm's push: works until it is disarmed.
  var alarmLink: URL {
    guard let pass = state.pass else { return Live.link }
    return URL(string: "https://\(Live.host)/v/\(Live.id)#\(pass)")!
  }

  private var active: Bool { running || wanted }

  func start(_ recorder: Recorder?, state: LiveState) {
    self.recorder = recorder
    self.state = state
    running = true
    if task == nil { connect() } else { send(state: state) }
    watchersChanged()
  }

  /// Between sessions: `on` keeps the socket open, showing `idle`, so a paired phone sees this Mac
  /// and can start it; also while a pairing code is on show, to hear the phone claim it. Off closes
  /// it, unless a session is running.
  func keepOpen(_ on: Bool, idle: LiveState) {
    wanted = on
    guard !running else { return }
    if on {
      state = idle
      if task == nil { connect() } else { send(state: idle) }
    } else {
      viewers = 0
      close(sendingLast: false)
    }
  }

  /// Changes the state and sends it once, with an event appended when `event` is given: the relay
  /// reads a change and the event that explains it together.
  func update(event e: String? = nil, key k: String? = nil, at: Date = Date(), _ change: (inout LiveState) -> Void) {
    change(&state)
    if let e { state.events.append(.init(t: LiveState.ms(at), e: e, k: k)) }
    send(state: state)
  }

  func event(_ e: String, _ k: String? = nil, at: Date = Date()) {
    update(event: e, key: k, at: at) { _ in }
  }

  /// A trigger: a fresh pass for the push link.
  @discardableResult
  func alarm() -> String {
    let pass = Live.random(16)
    state.pass = pass
    return pass
  }

  /// The session is over, and its last state is sent: closes the socket, unless it stays open for a phone.
  func stop() {
    running = false
    recorder?.setLive(nil)
    recorder = nil
    guard !wanted else { return }
    viewers = 0
    close(sendingLast: true)
  }

  /// Answers a command, so the phone is never left waiting. `then` runs once the answer is out.
  func ack(_ id: String, ok: Bool = true, why: String? = nil, then: (() -> Void)? = nil) {
    var body: [String: Any] = ["id": id, "ok": ok]
    if let why { body["why"] = why }
    guard let t = task, let data = try? JSONSerialization.data(withJSONObject: ["ack": body]) else {
      then?()
      return
    }
    t.send(.string(String(decoding: data, as: UTF8.self))) { _ in DispatchQueue.main.async { then?() } }
  }

  /// A finished session, for the iPhone's history. Held until there is a connection to send it on.
  func session(_ record: SessionRecord) {
    guard let data = try? JSONEncoder().encode(["session": record]) else { return }
    unsent.append(String(decoding: data, as: UTF8.self))
    if unsent.count > 30 { unsent.removeFirst() }
    flushSessions()
  }

  /// One photo of the alarm, for the page's photo grid.
  func upload(_ photo: Data, at date: Date = Date(), attempt: Int = 1) {
    var url = URLComponents(string: "https://\(Live.host)/photo/\(Live.key)")!
    url.queryItems = [.init(name: "t", value: String(LiveState.ms(date)))]
    if let pass = state.pass { url.queryItems!.append(.init(name: "pass", value: pass)) }
    var request = URLRequest(url: url.url!, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
    request.httpBody = photo
    URLSession.shared.dataTask(with: request) { _, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      DispatchQueue.main.async {
        if status == 200 { log("photo uploaded, \(photo.count / 1024) KB"); return }
        log("photo upload failed (attempt \(attempt)): \(error?.localizedDescription ?? "HTTP \(status)")")
        guard attempt < 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.upload(photo, at: date, attempt: attempt + 1) }
      }
    }.resume()
  }

  /// Drops the connection and, when one is still wanted, makes it again at once under the current
  /// key: after a reset the old room is gone, and after a sleep the old socket is dead.
  func reconnect() {
    if let t = task {
      task = nil
      t.cancel(with: .goingAway, reason: nil)
    }
    ping?.invalidate()
    ping = nil
    retryDelay = 5
    setViewers(0)
    if active { connect() }
  }

  private func connect() {
    let t = URLSession.shared.webSocketTask(with: URL(string: "wss://\(Live.host)/cam/\(Live.key)")!)
    task = t
    sending = false
    t.resume()
    // Sent before the handshake completes: the task queues them.
    t.send(.string(#"{"hello":{"token":"\#(Live.token)","v":\#(helloVersion)}}"#)) { _ in }
    send(state: state)
    flushSessions()
    receive(t)
    ping?.invalidate()
    ping = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      t.sendPing { error in
        if let error { DispatchQueue.main.async { self?.failed(t, error) } }
      }
    }
  }

  /// Closes the socket; `sendingLast` puts the final state on it first.
  private func close(sendingLast: Bool) {
    ping?.invalidate()
    ping = nil
    guard let t = task else { return }
    task = nil
    if sendingLast {
      t.send(.string(encoded(state))) { _ in t.cancel(with: .goingAway, reason: nil) }
    } else {
      t.cancel(with: .goingAway, reason: nil)
    }
  }

  private func encoded(_ state: LiveState) -> String {
    String(data: (try? JSONEncoder().encode(["state": state])) ?? Data(), encoding: .utf8) ?? "{}"
  }

  private func send(state: LiveState) {
    guard let t = task else { return }
    t.send(.string(encoded(state))) { error in
      if let error { log("live state not sent: \(error.localizedDescription)") }
    }
  }

  private func flushSessions() {
    guard let t = task, !unsent.isEmpty else { return }
    let queued = unsent
    unsent = []
    for text in queued {
      t.send(.string(text)) { [weak self] error in
        guard error != nil else { return }
        DispatchQueue.main.async { self?.unsent.append(text) }
      }
    }
  }

  private func receive(_ t: URLSessionWebSocketTask) {
    t.receive { [weak self] result in
      DispatchQueue.main.async {
        guard let self, t === self.task else { return }
        switch result {
        case .failure(let error):
          self.failed(t, error)
        case .success(let message):
          if case .string(let text) = message { self.handle(text) }
          self.receive(t)
        }
      }
    }
  }

  /// What the relay says: how many pages may see the camera (on connect and on every change), a
  /// phone that claimed the pairing code, and the owner's commands. Only a command that came as
  /// `{"cmd": ..., "from": "phone"}` is acted on.
  private func handle(_ text: String) {
    guard let json = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return }
    retryDelay = 5
    if let n = json["viewers"] as? Int { setViewers(n) }
    if let paired = json["paired"] as? [String: Any] { onPaired?(paired["device"] as? String ?? "") }
    if let cmd = json["cmd"] as? [String: Any], json["from"] as? String == "phone" {
      if let command = PhoneCommand.decode(cmd) {
        onCommand?(command)
      } else if let id = cmd["id"] as? String, (1...24).contains(id.count) {
        ack(id, ok: false, why: "bad-command")
      }
    }
  }

  private func failed(_ t: URLSessionWebSocketTask, _ error: Error) {
    guard t === task else { return }
    log("live relay: \(error.localizedDescription); \(active ? "retrying in \(Int(retryDelay)) s" : "closed")")
    task = nil
    t.cancel()
    ping?.invalidate()
    ping = nil
    setViewers(0)
    let delay = retryDelay
    retryDelay = min(retryDelay * 2, 60)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self, active, task == nil else { return }  // stopped meanwhile
      connect()
    }
  }

  private func setViewers(_ n: Int) {
    guard n != viewers else { return }
    viewers = n
    log("live view: \(n) watching")
    watchersChanged()
  }

  /// Frames go to the relay only while someone may see them.
  private func watchersChanged() {
    recorder?.setLive(viewers > 0 ? { [weak self] jpeg in DispatchQueue.main.async { self?.send(jpeg) } } : nil)
  }

  /// Drops frames while one is still in flight, so a slow network shows fewer, fresh frames.
  private func send(_ jpeg: Data) {
    guard let t = task, !sending else { return }
    sending = true
    t.send(.data(jpeg)) { [weak self] _ in DispatchQueue.main.async { self?.sending = false } }
  }
}
