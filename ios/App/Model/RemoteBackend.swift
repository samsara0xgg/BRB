import Foundation
import UIKit

/// The real thing: sockets and HTTP to the relay.
@MainActor
final class RemoteBackend: Backend {
  let isDemo = false
  private var watchers: [String: RelayWatcher] = [:]
  private var waiting: [String: CheckedContinuation<CommandResult?, Never>] = [:]

  func attach(_ mac: MacModel) {
    guard watchers[mac.id] == nil else { return }
    let watcher = RelayWatcher(api: RelayAPI(mac.paired))
    watcher.onEvent = { [weak self, weak mac] event in
      guard let self, let mac else { return }
      switch event {
      case .connecting: if mac.link == .down { mac.setLink(.connecting) }
      case .connected: mac.setLink(.live); mac.queued = false
      case .down: mac.setLink(.down)
      case .view(let view, let raw): mac.apply(view: view, raw: raw)
      case .frame(let data): mac.apply(frame: data)
      case .ack(let id, let ok, let why): self.resolve(id, ok ? .done : .failed(why ?? "failed"))
      }
    }
    watchers[mac.id] = watcher
    watcher.start()
  }

  func detach(_ mac: MacModel) {
    watchers[mac.id]?.stop()
    watchers[mac.id] = nil
  }

  func refresh(_ mac: MacModel) async {
    guard let view = try? await RelayAPI(mac.paired).view() else { return }
    mac.apply(view: view)
  }

  func send(_ command: Command, to mac: MacModel) async -> CommandResult {
    let cid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
    let api = RelayAPI(mac.paired)
    do {
      let delivered = try await api.send(command, id: cid)
      if !delivered {
        mac.queued = true
        return .queued
      }
      // The Mac answers on the socket if we have one open; without it, trust the relay.
      guard watchers[mac.id] != nil, mac.link == .live else { return .done }
      return await ack(cid, timeout: 6) ?? .done
    } catch let e as RelayError {
      if e.status == 403 { return .failed("forbidden") }
      return .failed(e.why)
    } catch {
      return .failed("net")
    }
  }

  private func ack(_ id: String, timeout: TimeInterval) async -> CommandResult? {
    await withCheckedContinuation { cont in
      waiting[id] = cont
      Task { [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        self?.resolve(id, nil)
      }
    }
  }

  private func resolve(_ id: String, _ result: CommandResult?) {
    guard let cont = waiting.removeValue(forKey: id) else { return }
    cont.resume(returning: result)
  }

  func history(of mac: MacModel) async throws -> [SessionRecord] { try await RelayAPI(mac.paired).history() }

  func photo(_ ms: Ms, of mac: MacModel) async -> UIImage? {
    guard let data = try? await RelayAPI(mac.paired).photo(ms) else { return nil }
    return UIImage(data: data)
  }

  func deleteSession(_ id: String, of mac: MacModel) async throws { try await RelayAPI(mac.paired).deleteSession(id) }
  func deleteMedia(of mac: MacModel) async throws { try await RelayAPI(mac.paired).deleteAllMedia() }

  func claim(_ code: PairingCode, device: String) async throws -> Claimed {
    switch code {
    case .qr(let host, let c): return try await RelayAPI.claim(host: host, code: c, device: device)
    case .digits(let d): return try await RelayAPI.claim(host: RelayDefaults.host, code: d, device: device)
    }
  }

  func register(_ reg: DeviceRegistration, for mac: MacModel) async { try? await RelayAPI(mac.paired).register(reg) }
  func unregister(dev: String, for mac: MacModel) async { try? await RelayAPI(mac.paired).unregister(dev: dev) }
  func testPush(for mac: MacModel) async throws { try await RelayAPI(mac.paired).testPush() }
}
