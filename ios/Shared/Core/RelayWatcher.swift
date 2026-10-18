import Foundation

/// One viewer socket to one Mac's room: `WS /watch/<id>?t=<token>`. Keeps itself connected, with a
/// ping every 25 seconds and a growing pause between tries, and reports what arrives.
@MainActor
final class RelayWatcher {
  enum Event {
    case connecting
    case connected
    case view(RelayView, raw: Data)
    case frame(Data)
    case ack(id: String, ok: Bool, why: String?)
    case down
  }

  private let api: RelayAPI
  private var loop: Task<Void, Never>?
  private var socket: URLSessionWebSocketTask?
  var onEvent: ((Event) -> Void)?

  init(api: RelayAPI) { self.api = api }

  deinit { loop?.cancel() }

  var isRunning: Bool { loop != nil }

  func start() {
    guard loop == nil else { return }
    loop = Task { [weak self] in await self?.run() }
  }

  func stop() {
    loop?.cancel()
    loop = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
  }

  /// Sends a command down the socket. False when there is no socket right now.
  func send(_ command: Command, id: String) async -> Bool {
    guard let socket, let data = try? JSONSerialization.data(withJSONObject: ["cmd": command.body(id: id)]),
      let text = String(data: data, encoding: .utf8)
    else { return false }
    do {
      try await socket.send(.string(text))
      return true
    } catch {
      return false
    }
  }

  private func run() async {
    var backoff = 1.0
    while !Task.isCancelled {
      let ws = URLSession.shared.webSocketTask(with: api.watchURL)
      socket = ws
      ws.resume()
      onEvent?(.connecting)
      let pinger = Task {
        while !Task.isCancelled {
          try? await Task.sleep(nanoseconds: 25_000_000_000)
          if Task.isCancelled { return }
          ws.sendPing { error in if error != nil { ws.cancel(with: .abnormalClosure, reason: nil) } }
        }
      }
      var first = true
      do {
        while !Task.isCancelled {
          let message = try await ws.receive()
          if first {
            first = false
            backoff = 1
            onEvent?(.connected)
          }
          handle(message)
        }
      } catch {}
      pinger.cancel()
      ws.cancel(with: .goingAway, reason: nil)
      if socket === ws { socket = nil }
      if Task.isCancelled { break }
      onEvent?(.down)
      try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
      backoff = min(backoff * 2, 20)
    }
  }

  private func handle(_ message: URLSessionWebSocketTask.Message) {
    switch message {
    case .data(let d):
      onEvent?(.frame(d))
    case .string(let s):
      guard let data = s.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      else { return }
      if let a = j["ack"] as? [String: Any], let id = a["id"] as? String {
        onEvent?(.ack(id: id, ok: (a["ok"] as? NSNumber)?.boolValue ?? false, why: a["why"] as? String))
      } else if j["level"] != nil || j["state"] != nil {
        onEvent?(.view(RelayView(json: j), raw: data))
      }
    @unknown default: break
    }
  }
}
