import AppKit

/// Watches every keyboard, mouse and trackpad event of the session. Volume, mute and brightness keys
/// are the owner's to use while armed: they pass through and never count as input. Everything else
/// is reported through `onInput`, and swallowed while `shouldBlock()` says so, so a stranger's first
/// keystroke never lands in an open terminal.
final class InputTap {
  /// One event that counts as someone at the laptop.
  struct Input {
    let kind: Trigger       // .keyboard, .trackpad or .powerKey
    let what: String        // for the log
    let keyCode: Int64?
    let location: CGPoint   // the pointer, in global display coordinates (top-left origin)
  }

  var onInput: (Input) -> Void = { _ in }
  var shouldBlock: () -> Bool = { false }
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  // NX_SYSDEFINED subtype 8 = media/brightness keys; key codes from IOKit's ev_keymap.h.
  private static let ownerKeys: [Int: String] = [0: "volume up", 1: "volume down", 2: "brightness up", 3: "brightness down", 7: "mute"]
  // Some keyboards send these as plain key codes instead.
  private static let ownerKeyCodes: [Int64: String] = [72: "volume up", 73: "volume down", 74: "mute", 144: "brightness up", 145: "brightness down"]
  private static let systemDefined: UInt32 = 14
  private static let types: [UInt32] = [1, 2, 3, 4, 5, 6, 7, 10, 11, 12, 14, 18, 19, 20, 22, 25, 26, 27, 29, 30, 31, 32, 34]

  /// Returns false when the event tap cannot be created (Accessibility not granted).
  func start(listenOnly: Bool = false) -> Bool {
    let mask = InputTap.types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
    let me = Unmanaged.passUnretained(self).toOpaque()
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                      options: listenOnly ? .listenOnly : .defaultTap, eventsOfInterest: mask,
                                      callback: { _, type, event, ctx in
      let me = Unmanaged<InputTap>.fromOpaque(ctx!).takeUnretainedValue()
      return me.handle(type, event)
    }, userInfo: me) else { return false }
    self.tap = tap
    source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    return true
  }

  func stop() {
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil
    source = nil
  }

  /// Name of the owner key this event is, or nil when it is ordinary input.
  static func ownerKey(_ type: CGEventType, _ event: CGEvent) -> String? {
    if type.rawValue == systemDefined {
      guard let ns = NSEvent(cgEvent: event) else { return "system event" }
      switch ns.subtype.rawValue {
      case 8: return ownerKeys[(ns.data1 & 0xFFFF_0000) >> 16]  // media / brightness keys
      case 1: return nil  // power / Touch ID key pressed: someone is at the laptop
      default: return "system event"  // not a key press
      }
    }
    if type == .keyDown || type == .keyUp {
      return ownerKeyCodes[event.getIntegerValueField(.keyboardEventKeycode)]
    }
    return nil
  }

  static func input(_ type: CGEventType, _ event: CGEvent) -> Input {
    var code: Int64?
    let kind: Trigger, what: String
    switch type {
    case .keyDown, .keyUp:
      code = event.getIntegerValueField(.keyboardEventKeycode)
      kind = .keyboard
      what = "key \(code ?? -1)"
    case .flagsChanged:
      kind = .keyboard
      what = "modifier key"
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
      kind = .trackpad
      what = "trackpad move"
    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
      kind = .trackpad
      what = "click"
    case .scrollWheel:
      kind = .trackpad
      what = "scroll"
    default:
      if type.rawValue == systemDefined {
        let power = NSEvent(cgEvent: event)?.subtype.rawValue == 1
        kind = power ? .powerKey : .keyboard
        what = power ? "power key" : "media key"
      } else {
        kind = .trackpad
        what = "trackpad gesture \(type.rawValue)"
      }
    }
    return Input(kind: kind, what: what, keyCode: code, location: event.location)
  }

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    if InputTap.ownerKey(type, event) != nil { return Unmanaged.passUnretained(event) }
    onInput(InputTap.input(type, event))
    return shouldBlock() ? nil : Unmanaged.passUnretained(event)
  }
}
