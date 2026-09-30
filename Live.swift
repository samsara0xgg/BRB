import CryptoKit
import Foundation

/// What the phone page shows, sent to the relay whenever it changes.
struct LiveState: Encodable {
  struct Event: Encodable {
    let t: Int64      // ms since 1970
    let e: String     // armed, triggered, photo, siren, disarmed, cancelled, warning
    let k: String?    // the trigger or the disarm, for the page to name
  }

  var v = 2
  var phase = "idle"  // idle, arming, armed, triggered
  var since: Int64 = 0
  var place = ""
  var note = ""
  var push = false
  var test = false
  var camera = false
  var trigger: String?
  var at: Int64?
  var siren = false
  var bumps = 0
  var events: [Event] = []
  var pass: String?

  static func ms(_ d: Date) -> Int64 { Int64(d.timeIntervalSince1970 * 1000) }
}

/// The phone page, through the GuardMode relay (relay/, a Cloudflare Worker). From the countdown on
/// the Mac holds a WebSocket to the relay and keeps it told what is happening; camera frames flow
/// only after a trigger and only while an allowed page is open. Photos of an alarm are kept by the
/// relay for 30 days.
///
/// Who sees what: the link in the panel carries the owner's token after `#` (never sent in a request
/// line, so never in a server log), and shows everything. The link in an alarm push carries a pass
/// that works only until that alarm is disarmed, because ntfy keeps its messages. Without either,
/// the page shows only whether the Mac is guarded.
final class Live {
  static let host = "guardmode-relay.guardmode-gf1n2.workers.dev"

  /// The Mac's secret: it connects as the camera with it.
  static var key: String { stored("liveKey", length: 32) }
  /// The owner's viewing token.
  static var token: String { stored("liveToken", length: 24) }

  static var id: String {
    SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
  }

  static var link: URL { URL(string: "https://\(host)/v/\(id)#\(token)")! }

  /// A new key and token: the old link stops working, and the relay forgets the old room.
  static func resetLink() {
    var request = URLRequest(url: URL(string: "https://\(host)/wipe/\(key)")!, timeoutInterval: 15)
    request.httpMethod = "POST"
    URLSession.shared.dataTask(with: request) { _, response, error in
      log("old live room wiped: \(error?.localizedDescription ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")")
    }.resume()
    UserDefaults.standard.removeObject(forKey: "liveKey")
    UserDefaults.standard.removeObject(forKey: "liveToken")
    log("live link reset")
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
  private var task: URLSessionWebSocketTask?
  private var recorder: Recorder?
  private var active = false
  private var viewers = 0
  private var sending = false
  private var ping: Timer?
  private var retryDelay = 5.0

  /// The link for this alarm's push: works until it is disarmed.
  var alarmLink: URL {
    guard let pass = state.pass else { return Live.link }
    return URL(string: "https://\(Live.host)/v/\(Live.id)#\(pass)")!
  }

  func start(_ recorder: Recorder?, state: LiveState) {
    self.recorder = recorder
    self.state = state
    active = true
    connect()
  }

  func update(_ change: (inout LiveState) -> Void) {
    change(&state)
    send(state: state)
  }

  func event(_ e: String, _ k: String? = nil, at: Date = Date()) {
    update { $0.events.append(.init(t: LiveState.ms(at), e: e, k: k)) }
  }

  /// A trigger: a fresh pass for the push link.
  @discardableResult
  func alarm() -> String {
    let pass = Live.random(16)
    state.pass = pass
    return pass
  }

  /// Sends the final state, then closes.
  func stop() {
    active = false
    recorder?.setLive(nil)
    recorder = nil
    ping?.invalidate()
    ping = nil
    viewers = 0
    guard let t = task else { return }
    task = nil
    let final = encoded(state)
    t.send(.string(final)) { _ in t.cancel(with: .goingAway, reason: nil) }
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

  private func connect() {
    let t = URLSession.shared.webSocketTask(with: URL(string: "wss://\(Live.host)/cam/\(Live.key)")!)
    task = t
    sending = false
    t.resume()
    // Sent before the handshake completes: the task queues them.
    t.send(.string(#"{"hello":{"token":"\#(Live.token)","v":2}}"#)) { _ in }
    send(state: state)
    receive(t)
    ping?.invalidate()
    ping = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      t.sendPing { error in
        if let error { DispatchQueue.main.async { self?.failed(t, error) } }
      }
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

  private func receive(_ t: URLSessionWebSocketTask) {
    t.receive { [weak self] result in
      DispatchQueue.main.async {
        guard let self, t === self.task else { return }
        switch result {
        case .failure(let error):
          self.failed(t, error)
        case .success(let message):
          // The relay says {"viewers": n}, counting pages allowed to see the camera, on connect and on every change.
          if case .string(let text) = message,
             let n = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])?["viewers"] as? Int {
            self.retryDelay = 5
            self.setViewers(n)
          }
          self.receive(t)
        }
      }
    }
  }

  private func failed(_ t: URLSessionWebSocketTask, _ error: Error) {
    guard t === task else { return }
    log("live relay: \(error.localizedDescription); retrying in \(Int(retryDelay)) s")
    task = nil
    t.cancel()
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
    recorder?.setLive(n > 0 ? { [weak self] jpeg in DispatchQueue.main.async { self?.send(jpeg) } } : nil)
  }

  /// Drops frames while one is still in flight, so a slow network shows fewer, fresh frames.
  private func send(_ jpeg: Data) {
    guard let t = task, !sending else { return }
    sending = true
    t.send(.data(jpeg)) { [weak self] _ in DispatchQueue.main.async { self?.sending = false } }
  }
}
