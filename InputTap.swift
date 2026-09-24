import AppKit

/// Watches every keyboard, mouse and trackpad event of the session. Volume, mute and brightness keys
/// are the owner's to use while armed: they pass through and never count as input. Everything else
/// is reported through `onInput`, and swallowed while `shouldBlock()` says so, so a stranger's first
/// keystroke never lands in an open terminal.
final class InputTap {
  var onInput: (String) -> Void = { _ in }
  var shouldBlock: () -> Bool = { false }
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?

  // NX_SYSDEFINED subtype 8 = media/brightness keys; key codes from IOKit's ev_keymap.h.
  private static let ownerKeys: [Int: String] = [0: "音量+", 1: "音量-", 2: "亮度+", 3: "亮度-", 7: "静音"]
  // Some keyboards send these as plain key codes instead.
  private static let ownerKeyCodes: [Int64: String] = [72: "音量+", 73: "音量-", 74: "静音", 144: "亮度+", 145: "亮度-"]
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
      guard let ns = NSEvent(cgEvent: event) else { return "系统事件" }
      switch ns.subtype.rawValue {
      case 8: return ownerKeys[(ns.data1 & 0xFFFF_0000) >> 16]  // media / brightness keys
      case 1: return nil  // power / Touch ID key pressed: someone is at the laptop
      default: return "系统事件"  // not a key press
      }
    }
    if type == .keyDown || type == .keyUp {
      return ownerKeyCodes[event.getIntegerValueField(.keyboardEventKeycode)]
    }
    return nil
  }

  static func describe(_ type: CGEventType, _ event: CGEvent) -> String {
    switch type {
    case .keyDown, .keyUp: return "按键 \(event.getIntegerValueField(.keyboardEventKeycode))"
    case .flagsChanged: return "修饰键"
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: return "触控板移动"
    case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp: return "点击"
    case .scrollWheel: return "滚动"
    default: return type.rawValue == systemDefined ? "系统按键（媒体键或电源键）" : "触控板手势 \(type.rawValue)"
    }
  }

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return Unmanaged.passUnretained(event)
    }
    if InputTap.ownerKey(type, event) != nil { return Unmanaged.passUnretained(event) }
    onInput(InputTap.describe(type, event))
    return shouldBlock() ? nil : Unmanaged.passUnretained(event)
  }
}
