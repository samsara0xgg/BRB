import Foundation

/// Which Mac a widget, a Live Activity or an intent means when nobody said which one.
enum BRBFocus {
  /// Alarm first, then arming, then guarding, else the first Mac.
  static func pick(_ macs: [MacSnapshot]) -> MacSnapshot? {
    if let m = macs.first(where: { $0.look.isAlarm }) { return m }
    if let m = macs.first(where: { $0.look == .arming }) { return m }
    if let m = macs.first(where: { $0.look.isGuarding }) { return m }
    return macs.first
  }

  /// Every Mac but the focus one, in the order they were paired.
  static func others(of focus: MacSnapshot?, in macs: [MacSnapshot]) -> [MacSnapshot] {
    macs.filter { $0.id != focus?.id }
  }

  enum Purpose { case start, stop, hush, status }

  /// The Mac an action is for when it was not named. nil means no Mac fits (nothing to stop, nobody alarming).
  static func target(_ macs: [MacSnapshot], for purpose: Purpose) -> MacSnapshot? {
    switch purpose {
    case .start:
      // A Mac that is not guarding; an offline one still works, the relay holds the command for 30 s.
      return macs.first(where: { $0.state.phase == .idle && $0.look != .offline })
        ?? macs.first(where: { $0.state.phase == .idle })
    case .stop:
      return macs.first(where: { $0.state.phase == .triggered })
        ?? macs.first(where: { $0.state.phase == .arming })
        ?? macs.first(where: { $0.state.phase == .armed })
    case .hush:
      return macs.first(where: { $0.state.phase == .triggered })
    case .status:
      return pick(macs)
    }
  }
}
