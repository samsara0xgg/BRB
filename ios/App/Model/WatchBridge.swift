import Foundation
import WatchConnectivity

/// Tells the Apple Watch which Macs are paired and whether Pro is unlocked.
final class WatchBridge: NSObject, WCSessionDelegate {
  static let shared = WatchBridge()
  private var pending: WatchPayload?

  func start() {
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func send(macs: [PairedMac], pro: Bool) {
    let payload = WatchPayload(macs: macs, pro: pro)
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated else {
      pending = payload
      return
    }
    guard session.isPaired, session.isWatchAppInstalled else { return }
    try? session.updateApplicationContext(payload.context)
  }

  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    if let pending, activationState == .activated {
      self.pending = nil
      send(macs: pending.macs, pro: pending.pro)
    }
  }
  func sessionDidBecomeInactive(_ session: WCSession) {}
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
  func sessionWatchStateDidChange(_ session: WCSession) {
    if let p = WatchPayload(context: session.applicationContext) { send(macs: p.macs, pro: p.pro) }
  }
}
