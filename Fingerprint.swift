import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

/// Disarms with a finger resting on Touch ID from the countdown on, with nothing on screen: an invisible
/// window holds the embedded Touch ID view instead of the system dialog. Measured 2026-09-24: the
/// finger only reaches a context whose view sits in the key window of the active app, so GuardMode
/// takes focus from the countdown on and hands it back after.
final class Fingerprint {
  private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
  }

  private var context: LAContext?
  private var window: KeyWindow?
  private var previousApp: NSRunningApplication?
  private var observer: NSObjectProtocol?
  private var onAccept: () -> Void = {}
  private var onReject: (String) -> Void = { _ in }

  func start(onAccept: @escaping () -> Void, onReject: @escaping (String) -> Void) {
    self.onAccept = onAccept
    self.onReject = onReject
    previousApp = NSWorkspace.shared.frontmostApplication
    let w = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
    w.alphaValue = 0
    w.level = .statusBar
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window = w
    // Another app taking focus would take the finger with it.
    observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
      self.focus()
    }
    evaluate()
  }

  func stop(returnFocus: Bool = true) {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    context?.invalidate()
    context = nil
    window?.orderOut(nil)
    window = nil
    if returnFocus { previousApp?.activate() }
    previousApp = nil
  }

  private func focus() {
    guard let window, !GuardApp.isScreenLocked() else { return }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  private func evaluate() {
    guard let window else { return }
    let ctx = LAContext()
    context = ctx
    window.contentView = LAAuthenticationView(context: ctx, controlSize: .small)
    focus()
    // Fingerprint lives as long as GuardApp, so the closures hold it strongly.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {  // the view is up first, as measured
      guard ctx === self.context else { return }
      ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "解除警戒模式") { ok, error in
        DispatchQueue.main.async {
          guard ctx === self.context else { return }  // stopped or replaced
          if ok { self.onAccept(); return }
          let code = (error as? LAError)?.code
          log("fingerprint: \(error?.localizedDescription ?? "-")")
          switch code {
          case .authenticationFailed, .biometryLockout:
            self.onReject("指纹不对")
            // Still running = the reject was ignored (countdown): listen again, unless Touch ID is locked out.
            if code == .authenticationFailed, ctx === self.context { self.evaluate() }
          case .biometryNotAvailable, .biometryNotEnrolled: break  // unlocking the Mac still disarms
          default:  // canceled by the system (focus lost): ask again; a locked screen disarms on unlock instead
            guard !GuardApp.isScreenLocked() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
              if ctx === self.context { self.evaluate() }
            }
          }
        }
      }
    }
  }
}
