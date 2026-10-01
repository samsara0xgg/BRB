import AppKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

/// Disarms with a finger resting on Touch ID from the countdown on, without the system dialog: the
/// embedded Touch ID view sits in the frosted veil's window, which is key while armed (audit M6), or,
/// with the veil switched off, in an invisible window of its own. Measured 2026-09-24: the finger only
/// reaches a context whose view sits in the key window of the active app, so BRB takes focus from
/// the countdown on and hands it back after.
final class Fingerprint {
  private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
  }

  private var context: LAContext?
  private var window: NSWindow?
  private var ownWindow = false
  private var view: LAAuthenticationView?
  private var previousApp: NSRunningApplication?
  private var observer: NSObjectProtocol?
  private var onAccept: () -> Void = {}
  private var onReject: () -> Void = {}

  /// `host` is the veil's window on the built-in screen; nil makes an invisible window instead.
  func start(in host: NSWindow?, onAccept: @escaping () -> Void, onReject: @escaping () -> Void) {
    self.onAccept = onAccept
    self.onReject = onReject
    previousApp = NSWorkspace.shared.frontmostApplication
    if let host {
      window = host
      ownWindow = false
    } else {
      let w = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
      w.alphaValue = 0
      w.level = .statusBar
      w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      window = w
      ownWindow = true
    }
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
    view?.removeFromSuperview()
    view = nil
    if ownWindow { window?.orderOut(nil) }
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
    let v = LAAuthenticationView(context: ctx, controlSize: .small)
    view?.removeFromSuperview()
    if ownWindow {
      window.contentView = v
    } else {
      v.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
      v.alphaValue = 0  // the notice says it in words
      window.contentView?.addSubview(v)
    }
    view = v
    focus()
    // Fingerprint lives as long as GuardApp, so the closures hold it strongly.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {  // the view is up first, as measured
      guard ctx === self.context else { return }
      ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: L("Stop guarding")) { ok, error in
        DispatchQueue.main.async {
          guard ctx === self.context else { return }  // stopped or replaced
          if ok { self.onAccept(); return }
          let code = (error as? LAError)?.code
          log("fingerprint: \(error?.localizedDescription ?? "-")")
          switch code {
          case .authenticationFailed, .biometryLockout:
            self.onReject()
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
