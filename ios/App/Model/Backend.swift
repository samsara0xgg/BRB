import Foundation
import UIKit

/// Where a Mac's news comes from and where commands go: the real relay, or the built-in demo.
@MainActor
protocol Backend: AnyObject {
  var isDemo: Bool { get }
  /// Start live updates for this Mac.
  func attach(_ mac: MacModel)
  func detach(_ mac: MacModel)
  /// Fetch the state once, without a socket (after a push, on foreground).
  func refresh(_ mac: MacModel) async
  func send(_ command: Command, to mac: MacModel) async -> CommandResult
  func history(of mac: MacModel) async throws -> [SessionRecord]
  func photo(_ ms: Ms, of mac: MacModel) async -> UIImage?
  func deleteSession(_ id: String, of mac: MacModel) async throws
  func deleteMedia(of mac: MacModel) async throws
  func claim(_ code: PairingCode, device: String) async throws -> Claimed
  func register(_ reg: DeviceRegistration, for mac: MacModel) async
  func unregister(dev: String, for mac: MacModel) async
  func testPush(for mac: MacModel) async throws
}

/// Pictures the alarm page, the history and the share card ask for again and again.
@MainActor
final class PhotoCache {
  static let shared = PhotoCache()
  private let cache = NSCache<NSString, UIImage>()
  private var inflight: [String: Task<UIImage?, Never>] = [:]

  func image(_ ms: Ms, of mac: MacModel, via backend: Backend) async -> UIImage? {
    let key = "\(mac.id)/\(ms)"
    if let hit = cache.object(forKey: key as NSString) { return hit }
    if let task = inflight[key] { return await task.value }
    let task = Task { await backend.photo(ms, of: mac) }
    inflight[key] = task
    let image = await task.value
    inflight[key] = nil
    if let image { cache.setObject(image, forKey: key as NSString) }
    return image
  }

  func cached(_ ms: Ms, of mac: MacModel) -> UIImage? { cache.object(forKey: "\(mac.id)/\(ms)" as NSString) }
  func forget(mac: MacModel) { cache.removeAllObjects() }
}
