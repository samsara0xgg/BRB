import CryptoKit
import Foundation

/// Live camera view in the phone's browser, through the GuardMode relay (relay/, a Cloudflare
/// Worker). While armed the Mac holds a WebSocket to the relay and sends small JPEG frames only
/// while someone has the page open. The link carries a hash of this Mac's key, so it lets you
/// watch but not pose as the camera.
final class Live {
  static let host = "guardmode-relay.guardmode-gf1n2.workers.dev"

  static var key: String {
    if let k = UserDefaults.standard.string(forKey: "liveKey") { return k }
    let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
    let k = String((0..<32).map { _ in alphabet.randomElement()! })
    UserDefaults.standard.set(k, forKey: "liveKey")
    return k
  }

  static var link: URL {
    let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
    return URL(string: "https://\(host)/v/\(id)")!
  }

  private var task: URLSessionWebSocketTask?
  private var recorder: Recorder?
  private var viewers = 0
  private var sending = false
  private var ping: Timer?
  private var retryDelay = 5.0

  func start(_ recorder: Recorder) {
    self.recorder = recorder
    connect()
  }

  func stop() {
    recorder?.setLive(nil)
    recorder = nil
    ping?.invalidate()
    ping = nil
    task?.cancel(with: .goingAway, reason: nil)
    task = nil
    viewers = 0
  }

  private func connect() {
    let t = URLSession.shared.webSocketTask(with: URL(string: "wss://\(Live.host)/cam/\(Live.key)")!)
    task = t
    sending = false
    t.resume()
    receive(t)
    ping?.invalidate()
    ping = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      t.sendPing { error in
        if let error { DispatchQueue.main.async { self?.failed(t, error) } }
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
          // The relay says {"viewers": n} on connect and whenever a page opens or closes.
          if case .string(let text) = message,
             let n = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Int])?["viewers"] {
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
      guard let self, recorder != nil, task == nil else { return }  // stopped meanwhile
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
