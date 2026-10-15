import Foundation
import WatchConnectivity

/// The Watch's end of WatchConnectivity. The iPhone sends the paired Macs and the Pro flag as the
/// application context (`WatchPayload.context`); this saves them where the app and the complication read
/// them (`Library.save`, `Prefs.pro`) and tells the model.
final class WatchLink: NSObject, WCSessionDelegate {
  static let shared = WatchLink()

  /// Called on the main actor after a payload was saved.
  var onChange: (@MainActor () -> Void)?

  /// Activates the session. Safe to call more than once.
  func start() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
    if session.activationState == .activated { apply(session.receivedApplicationContext) }
  }

  // MARK: WCSessionDelegate

  func session(
    _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?
  ) {
    if activationState == .activated { apply(session.receivedApplicationContext) }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    apply(applicationContext)
  }

  // MARK: payload

  private func apply(_ context: [String: Any]) {
    guard let payload = WatchPayload(context: context) else { return }
    let before = Library.macs()
    Library.save(payload.macs)
    Prefs.pro = payload.pro
    // Forget what was cached for a Mac the iPhone no longer has.
    for old in before where !payload.macs.contains(where: { $0.id == old.id }) {
      Library.forget(id: old.id)
    }
    Task { @MainActor in
      self.onChange?()
    }
  }
}
