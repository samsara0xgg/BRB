import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Design A, "frosted glass": while armed every screen turns to frosted glass with one line on it. The
/// built-in screen carries the notice; other screens get the frost and one small line. The windows sit
/// at the shielding level, above the menu bar, the Dock, full-screen apps and notification banners
/// (audit H5), ignore the mouse (InputTap swallows input as before), and keep the display awake. The
/// built-in screen's window is key and holds the Touch ID view (audit M6).
final class Veil {
  let model = VeilModel()
  /// A screen came or went and the windows were rebuilt: the Touch ID view needs the new host.
  var onRebuild: () -> Void = {}
  /// The notice reached the menu-bar shield (or there was no notice): the shield turns green.
  var onLanded: () -> Void = {}
  private var windows: [VeilWindow] = []
  private var screens: NSObjectProtocol?
  private var awake: IOPMAssertionID = 0
  private var pending: [DispatchWorkItem] = []

  /// The window on the built-in screen.
  var host: NSWindow? { windows.first { $0.showsNotice } ?? windows.first }
  var isUp: Bool { !windows.isEmpty }

  private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

  /// Counting down: the fog spreads out from the notice and reaches the corners as it starts guarding.
  /// The ring is drawn from `countdownFrom`, so it and the menu-bar shield never drift apart.
  func countdown(_ seconds: Int) {
    open()
    model.remaining = seconds
    model.countdownFrom = Date()
    model.countdownSeconds = Double(seconds)
    model.ringLive = true
    model.stage = .countdown
    windows.forEach { $0.frost.spread(over: Double(seconds)) }
  }

  /// Straight to guarding, fully frosted: a session resumed after a restart.
  func guarding() {
    open()
    model.ringLive = false
    model.stage = .armed
    windows.forEach { $0.frost.cover() }
  }

  /// The moment it starts: the ring flashes white, a shock wave leaves its rim and the glass lights
  /// up, then the glass stretches into the notice (audit C3).
  func armed() {
    guard model.stage == .countdown, !still else {
      model.ringLive = false
      model.stage = .armed
      return
    }
    model.shockAt = Date()
    model.shock += 1
    later(0.13) { self.model.stage = .armed }
    later(0.5) { self.model.ringLive = false }
  }

  /// Red spreads from where the Mac was touched: `pointer` in global display coordinates (top-left
  /// origin) for a click or a touch, else `origin`, a unit point on the notice's screen.
  func alarm(pointer: CGPoint?, origin: CGPoint) {
    guard isUp else { return }
    if let pointer, let spot = Veil.locate(pointer) {
      model.originDisplay = spot.display
      model.origin = spot.unit
    } else {
      model.originDisplay = (host as? VeilWindow)?.displayID ?? 0
      model.origin = origin
    }
    model.alarmAt = Date()
    model.ringLive = false
    model.stage = .alarm
    model.flinch += 1  // the notice flinches, as if touched (audit C4)
    windows.forEach { $0.frost.alarm(true) }
  }

  /// Back: the fog clears from the bottom-right, where Touch ID is; the notice says what happened,
  /// then flies into the menu-bar shield at `target` (its screen frame). After an alarm it stays
  /// 4.2 s instead of 2.6, long enough to read (audit A6).
  func welcome(_ welcome: Welcome, toward target: NSRect?) {
    guard isUp else { return onLanded() }
    pending.forEach { $0.cancel() }
    pending.removeAll()
    model.welcome = welcome
    model.leaveTarget = target.flatMap(noticePoint)
    model.ringLive = false
    model.stage = .welcome
    windows.forEach {
      $0.frost.alarm(false)
      $0.frost.melt()
    }
    let hold = welcome.alarmed ? 4.2 : 2.6
    let flight = still ? 0.2 : 0.74
    later(hold) { self.model.leaving = true }
    later(hold + flight) { self.onLanded() }
    later(hold + flight + 0.08) { self.close() }
  }

  /// Cancelled during the countdown: the ring unwinds the way it came, the glass follows and the fog
  /// pulls back (audit C6).
  func cancel() {
    guard isUp else { return }
    pending.forEach { $0.cancel() }
    pending.removeAll()
    let p = Date().timeIntervalSince(model.countdownFrom) / max(model.countdownSeconds, 0.1)
    model.unwindFrom = model.stage == .countdown ? min(max(p, 0), 1) : 0
    model.unwindAt = Date()
    model.cancelling = true
    windows.forEach { $0.frost.retreat() }
    later(0.18) { self.model.stage = .hidden }
    later(0.65) { self.close() }
  }

  func close() {
    pending.forEach { $0.cancel() }
    pending.removeAll()
    windows.forEach { $0.orderOut(nil) }
    windows.removeAll()
    if let screens { NotificationCenter.default.removeObserver(screens) }
    screens = nil
    model.stage = .hidden
    model.leaving = false
    model.cancelling = false
    model.ringLive = false
    keepDisplayOn(false)
  }

  private func open() {
    pending.forEach { $0.cancel() }
    pending.removeAll()
    model.leaving = false
    model.cancelling = false
    guard windows.isEmpty else { return }
    build()
    screens = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
      self?.rebuild()
    }
    keepDisplayOn(true)
  }

  private func build() {
    let main = NSScreen.screens.first { $0.isBuiltIn } ?? NSScreen.main ?? NSScreen.screens.first
    windows = NSScreen.screens.map { VeilWindow.make(screen: $0, model: model, showsNotice: $0 == main) }
    windows.forEach { $0.orderFrontRegardless() }
  }

  /// Screens changed while up: new windows at the current stage, fully frosted, no animation.
  private func rebuild() {
    guard !windows.isEmpty, model.stage != .hidden, model.stage != .welcome else { return }
    windows.forEach { $0.orderOut(nil) }
    build()
    windows.forEach {
      $0.frost.cover()
      $0.frost.alarm(model.stage == .alarm)
    }
    log("veil: screens changed, \(windows.count) now")
    onRebuild()
  }

  private func later(_ seconds: Double, _ work: @escaping () -> Void) {
    let item = DispatchWorkItem(block: work)
    pending.append(item)
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
  }

  /// A frame in screen coordinates, as points from the top-left of the notice's screen.
  private func noticePoint(_ r: NSRect) -> CGPoint? {
    guard let f = host?.screen?.frame, f.contains(NSPoint(x: r.midX, y: r.midY)) else { return nil }
    return CGPoint(x: r.midX - f.minX, y: f.maxY - r.midY)
  }

  /// A global display point (top-left origin on the primary display): its screen, and where on it.
  static func locate(_ p: CGPoint) -> (display: CGDirectDisplayID, unit: CGPoint)? {
    guard let primary = NSScreen.screens.first else { return nil }
    let cocoa = NSPoint(x: p.x, y: primary.frame.maxY - p.y)
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cocoa, $0.frame, false) }) else { return nil }
    let f = screen.frame
    return (screen.displayID, CGPoint(x: (cocoa.x - f.minX) / f.width, y: (f.maxY - cocoa.y) / f.height))
  }

  /// Without this the display sleeps after its usual idle time and the notice goes dark with it.
  private func keepDisplayOn(_ on: Bool) {
    if on && awake == 0 {
      let result = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "BRB is guarding this Mac" as CFString, &awake)
      if result != kIOReturnSuccess {
        log("display-sleep assertion failed: \(result)")
        awake = 0
      }
    } else if !on && awake != 0 {
      IOPMAssertionRelease(awake)
      awake = 0
    }
  }
}

/// What the veil shows. One model drives the windows on every screen.
final class VeilModel: ObservableObject {
  enum Stage { case hidden, countdown, armed, alarm, welcome }
  @Published var stage = Stage.hidden
  @Published var remaining = 5
  @Published var test = false
  @Published var note = ""
  @Published var armedAt = Date()
  /// The camera is buffering, so "touching it is recorded" is true (audit H4: say only what is true).
  @Published var recording = true
  @Published var pushOn = false
  @Published var alarmAt = Date()
  @Published var originDisplay: CGDirectDisplayID = 0
  @Published var origin = CGPoint(x: 0.5, y: 0.6)
  /// The lock screen is up: nothing here is visible, so the pulse stops drawing.
  @Published var locked = false
  @Published var welcome = Welcome(title: "", sub: "", chips: [], alarmed: false)
  @Published var leaving = false
  @Published var leaveTarget: CGPoint?
  /// When the countdown started and how long it runs: the ring is drawn from these.
  @Published var countdownFrom = Date()
  @Published var countdownSeconds = 5.0
  /// The ring is drawn: from the countdown until its flash has faded, and while it unwinds.
  @Published var ringLive = false
  /// Each increment: the white flash and the shock wave as guarding starts.
  @Published var shock = 0
  @Published var shockAt = Date.distantPast
  /// Cancelled: the ring unwinds from `unwindFrom` and the glass fades.
  @Published var cancelling = false
  @Published var unwindFrom = 0.0
  @Published var unwindAt = Date.distantPast
  /// Each increment: the notice flinches as an alarm starts.
  @Published var flinch = 0
}

private final class VeilWindow: NSWindow {
  private(set) var frost: FrostView!
  private(set) var showsNotice = false
  private(set) var displayID: CGDirectDisplayID = 0

  static func make(screen: NSScreen, model: VeilModel, showsNotice: Bool) -> VeilWindow {
    let w = VeilWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.showsNotice = showsNotice
    w.displayID = screen.displayID
    w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.isReleasedWhenClosed = false
    w.animationBehavior = .none
    w.appearance = NSAppearance(named: .darkAqua)
    let size = screen.frame.size
    let root = NSView(frame: NSRect(origin: .zero, size: size))
    let frost = FrostView(frame: root.bounds)
    root.addSubview(frost)
    let notice = NSHostingView(rootView: VeilView(model: model, showsNotice: showsNotice, displayID: screen.displayID))
    notice.frame = root.bounds
    notice.autoresizingMask = [.width, .height]
    root.addSubview(notice)
    w.contentView = root
    w.frost = frost
    w.setFrame(screen.frame, display: false)
    return w
  }

  override var canBecomeKey: Bool { true }
}

extension NSScreen {
  var displayID: CGDirectDisplayID {
    deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
  }

  var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }
}

// MARK: - the frost

/// The system's behind-window blur, a 38 % ink tint and a fine grain, revealed through a mask that
/// spreads from the notice (arming), pulls back (cancel) or opens from the bottom-right (welcome).
/// With Reduce Transparency the blur gives way to a 92 % dark fill; with Reduce Motion every change
/// is a 200 ms fade.
private final class FrostView: NSView {
  private enum Shape {
    case spread(Double)  // fog reach, 0 = none, 1 = the whole screen
    case melt(Double)    // hole reach from the bottom-right corner, 1 = all clear
  }

  private let effect = NSVisualEffectView()
  private let shade = NSView()
  private let tint = CAGradientLayer()
  private let grain = GrainLayer()
  private let shadeMask = CALayer()
  private var shape = Shape.spread(0)
  private var timer: Timer?
  private let solid = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
  private let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

  override init(frame: NSRect) {
    super.init(frame: frame)
    autoresizingMask = [.width, .height]
    effect.frame = bounds
    effect.autoresizingMask = [.width, .height]
    effect.blendingMode = .behindWindow
    effect.material = .fullScreenUI
    effect.state = .active
    effect.isHidden = solid
    addSubview(effect)
    shade.frame = bounds
    shade.autoresizingMask = [.width, .height]
    shade.layer = CALayer()
    shade.wantsLayer = true
    tint.startPoint = CGPoint(x: 0.5, y: 1)  // layer space is y-up: the first color is the top
    tint.endPoint = CGPoint(x: 0.5, y: 0)
    tint.colors = colors(alarm: false)
    grain.contentsScale = 1
    grain.needsDisplayOnBoundsChange = true
    shade.layer?.addSublayer(tint)
    shade.layer?.addSublayer(grain)
    shade.layer?.mask = shadeMask
    addSubview(shade)
    layoutLayers()
    applyMask()
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override func setFrameSize(_ size: NSSize) {
    super.setFrameSize(size)
    layoutLayers()
  }

  /// A layer-hosting view leaves its sublayers to us.
  private func layoutLayers() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    tint.frame = shade.bounds
    grain.frame = shade.bounds
    shadeMask.frame = shade.bounds
    CATransaction.commit()
    grain.setNeedsDisplay()
  }

  /// Arming: over the countdown, as if someone breathed on the glass.
  func spread(over seconds: Double) {
    if still {
      set(.spread(1))
      alphaValue = 0
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        self.animator().alphaValue = 1
      }
      return
    }
    alphaValue = 1
    animate(seconds, .fog) { .spread($0) }
  }

  /// Fully frosted at once.
  func cover() {
    timer?.invalidate()
    alphaValue = 1
    set(.spread(1))
  }

  /// A cancelled countdown: the fog pulls back to the notice.
  func retreat() {
    if still {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        self.animator().alphaValue = 0
      }
      return
    }
    guard case .spread(let from) = shape else { return }
    animate(0.55, .retreat) { .spread(from * (1 - $0)) }
  }

  /// Welcome back: the fog clears from the bottom-right, where Touch ID is.
  func melt() {
    if still {
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.2
        self.animator().alphaValue = 0
      }
      return
    }
    animate(1.4, .melt) { .melt($0) }
  }

  func alarm(_ on: Bool) {
    CATransaction.begin()
    CATransaction.setAnimationDuration(still ? 0.2 : 0.6)
    tint.colors = colors(alarm: on)
    CATransaction.commit()
  }

  private func colors(alarm: Bool) -> [CGColor] {
    func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
      CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: solid ? 0.92 : a)
    }
    return alarm ? [c(72, 6, 16, 0.40), c(48, 4, 10, 0.58)] : [c(9, 13, 28, 0.38), c(9, 13, 28, 0.52)]
  }

  private func animate(_ seconds: Double, _ ease: Ease, _ shapeAt: @escaping (Double) -> Shape) {
    timer?.invalidate()
    let start = CACurrentMediaTime()
    let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      let p = min(1, (CACurrentMediaTime() - start) / seconds)
      self.set(shapeAt(ease(p)))
      if p >= 1 {
        timer.invalidate()
        self.timer = nil
      }
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  private func set(_ s: Shape) {
    shape = s
    applyMask()
  }

  private func applyMask() {
    if case .spread(let p) = shape, p >= 1 {  // steady state: no mask to composite
      effect.maskImage = nil
      shade.layer?.mask = nil
      return
    }
    guard let image = maskImage() else { return }
    effect.maskImage = NSImage(cgImage: image, size: bounds.size)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shadeMask.contents = image
    shadeMask.frame = shade.bounds
    if shade.layer?.mask == nil { shade.layer?.mask = shadeMask }
    CATransaction.commit()
  }

  /// A small alpha image of the fog, stretched over the screen.
  private func maskImage() -> CGImage? {
    let w = 96, h = max(8, Int((96 * bounds.height / max(bounds.width, 1)).rounded()))
    let aspect = Double(bounds.width / max(bounds.height, 1))
    var px = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h {
      for x in 0..<w {
        let u = (Double(x) + 0.5) / Double(w), v = (Double(y) + 0.5) / Double(h)  // v from the top
        px[(y * w + x) * 4 + 3] = UInt8((alpha(u, v, aspect) * 255).rounded())
      }
    }
    guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  private func alpha(_ u: Double, _ v: Double, _ aspect: Double) -> Double {
    switch shape {
    case .spread(let p):
      // radial-gradient(ellipse 72% 72% at 50% 44%, fog, transparent fog + 22%), fog -30% → 108%
      let fog = -0.30 + 1.38 * p
      let d = hypot(u - 0.5, v - 0.44) / 0.72
      return min(1, max(0, (fog + 0.22 - d) / 0.22))
    case .melt(let p):
      let reach = -0.22 + 1.46 * p
      let d = hypot((u - 0.97) * aspect, v - 1.04) / hypot(aspect, 1)
      return min(1, max(0, (d - reach) / 0.22))
    }
  }
}

/// Fine white grain, tiled from a small noise image.
private final class GrainLayer: CALayer {
  static let noise: CGImage? = {
    let n = 128
    var px = [UInt8](repeating: 0, count: n * n * 4)
    for i in 0..<(n * n) {
      let a = UInt8.random(in: 0...14)  // white at up to 5.5 %, premultiplied
      px[i * 4] = a
      px[i * 4 + 1] = a
      px[i * 4 + 2] = a
      px[i * 4 + 3] = a
    }
    guard let provider = CGDataProvider(data: Data(px) as CFData) else { return nil }
    return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }()

  override func draw(in ctx: CGContext) {
    guard let noise = GrainLayer.noise else { return }
    ctx.draw(noise, in: CGRect(x: 0, y: 0, width: noise.width, height: noise.height), byTiling: true)
  }
}

// MARK: - the notice

struct VeilView: View {
  @ObservedObject var model: VeilModel
  let showsNotice: Bool
  let displayID: CGDirectDisplayID
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { g in
      TimelineView(.animation(minimumInterval: nil, paused: model.stage != .alarm || model.locked)) { tl in
        let pulse = VeilView.pulse(tl.date.timeIntervalSince(model.alarmAt))
        ZStack {
          flood(g.size, pulse)
          if showsNotice {
            NoticeView(model: model, size: g.size, pulse: pulse)
          } else {
            MiniSign(model: model)
              .position(x: g.size.width / 2, y: g.size.height / 2)
          }
        }
      }
    }
    .ignoresSafeArea()
    .environment(\.colorScheme, .dark)
  }

  /// Once a second: full for 150 ms, then falling for 850 ms, in step with the soft beep.
  static func pulse(_ t: TimeInterval) -> Double {
    let f = t - floor(t)
    return f < 0.15 ? 1 : 1 - (f - 0.15) / 0.85
  }

  /// Red from the touch point: out over 800 ms, then pulsing with the beep.
  private func flood(_ size: CGSize, _ pulse: Double) -> some View {
    let on = model.stage == .alarm
    let o = model.originDisplay == displayID ? model.origin : CGPoint(x: 0.5, y: 0.5)
    let center = CGPoint(x: o.x * size.width, y: o.y * size.height)
    let corners = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
    let reach = (corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 1000) * 1.15
    return Theme.flood
      .opacity(on ? 0.2 + 0.26 * pulse : 0)
      .animation(.easeOut(duration: 0.4), value: on)
      .mask {
        Circle()
          .frame(width: reach * 2, height: reach * 2)
          .scaleEffect(on ? 1 : 0.01)
          .position(center)
          .blur(radius: 60)
          .animation(reduceMotion ? .easeInOut(duration: 0.2) : .timingCurve(0.2, 0.75, 0.25, 1, duration: 0.8), value: on)
      }
      .allowsHitTesting(false)
  }
}

/// The other screens: the same glass, smaller, with the shield and one line, so a second display
/// says what the built-in one says (audit C7).
private struct MiniSign: View {
  @ObservedObject var model: VeilModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let visible = model.stage != .hidden && !model.leaving && !model.cancelling
    HStack(spacing: 14) {
      ShieldGlyph(look: icon)
        .frame(width: 34, height: 34)
      Text(title)
        .font(.system(size: 28, weight: .semibold))
        .lineLimit(1)
        .contentTransition(.numericText(countsDown: true))
    }
    .foregroundStyle(.white)
    .padding(.leading, 22)
    .padding(.trailing, 30)
    .frame(height: 76)
    .fixedSize()
    .modifier(GlassCapsule(look: look, rim: 1.5))
    .animation(Theme.motion(Theme.glass, reduced: reduceMotion), value: model.stage)
    .animation(.default, value: model.remaining)
    .scaleEffect(visible ? 1 : 0.94)
    .opacity(visible ? 1 : 0)
    .animation(Theme.motion(Theme.out(0.45), reduced: reduceMotion), value: visible)
  }

  private var title: String {
    switch model.stage {
    case .countdown: L("Guarding starts in %ld s", model.remaining)
    case .alarm: L("Alarm raised")
    case .welcome: model.welcome.title
    default: L("Please don't touch")
    }
  }

  private var icon: ShieldGlyph.Look {
    switch model.stage {
    case .alarm: .alarm
    case .welcome: .clear
    default: .guarding
    }
  }

  private var look: GlassCapsule.Look {
    switch model.stage {
    case .alarm: .alarm
    case .welcome: .dark
    default: .clear
    }
  }
}

private struct NoticeView: View {
  @ObservedObject var model: VeilModel
  let size: CGSize
  let pulse: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorSchemeContrast) private var contrast
  @State private var appeared = false
  @State private var seal = 0.0
  @State private var shockScale: CGFloat = 1
  @State private var shockOpacity = 0.0

  var body: some View {
    let center = CGPoint(x: size.width / 2, y: size.height * 0.438)
    let stage = model.stage
    let counting = stage == .countdown && !model.cancelling
    let tagged = model.test && (stage == .armed || stage == .alarm)
    ZStack {
      shockRing.position(center)
      capsule.position(center)
      chips.position(x: center.x, y: center.y + 119)
      Color.clear
        .frame(width: 1, height: 1)
        .overlay(alignment: .top) {  // hangs from 142 pt under the ring's center, however tall it is
          countdownText
            .opacity(counting ? 1 : 0)
            .animation(counting ? .easeInOut(duration: 0.3).delay(0.5) : .easeOut(duration: 0.2), value: counting)
        }
        .position(x: center.x, y: center.y + 142)
      foot
        .opacity(stage == .armed ? 1 : 0)
        .animation(.easeInOut(duration: 0.5).delay(stage == .armed ? 0.5 : 0), value: stage)
        .position(x: center.x, y: size.height - 136)
      testTag
        .opacity(tagged ? 1 : 0)
        .offset(y: tagged ? 0 : -6)
        .animation(Theme.motion(.spring(duration: 0.4, bounce: 0.3), reduced: reduceMotion), value: tagged)
        .padding(EdgeInsets(top: 22, leading: 24, bottom: 0, trailing: 0))
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
    .frame(width: size.width, height: size.height)
    .opacity(stage == .hidden ? 0 : 1)
    .animation(.easeInOut(duration: 0.35), value: stage == .hidden)
    .modifier(Flight(leaving: model.leaving, anchor: UnitPoint(x: 0.5, y: 0.438), offset: leaveOffset(center), still: reduceMotion))
    .onChange(of: model.shock) { _, _ in shockwave() }
  }

  private func leaveOffset(_ center: CGPoint) -> CGSize {
    guard let t = model.leaveTarget else { return .zero }
    return CGSize(width: t.x - center.x, height: t.y - center.y)
  }

  // The same piece of glass is the countdown ring and the notice: it stretches from a circle into a
  // capsule instead of swapping one element for another.
  private var capsule: some View {
    let round = model.stage == .countdown || model.cancelling
    let counting = model.stage == .countdown && !model.cancelling
    let w: CGFloat = round ? 212 : SignLabel.width(title: title, sub: sub)
    let h: CGFloat = round ? 212 : (model.stage == .welcome ? 140 : 150)
    return ZStack {
      if model.ringLive {
        CountdownRing(model: model)
          .opacity(round ? 1 : 0)
          .animation(.easeOut(duration: 0.28), value: round)
      }
      Digits(value: model.remaining)
        .opacity(counting ? 1 : 0)
        .animation(.easeOut(duration: 0.28), value: counting)
      SignLabel(icon: icon, title: title, sub: sub, breathing: model.stage == .armed && !reduceMotion)
        .fixedSize()
        .id(title + "\n" + sub)  // a new sign cross-fades in while the glass changes shape
        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.4).delay(0.06)),
                                removal: .opacity.animation(.easeOut(duration: 0.3))))
        .opacity(round ? 0 : 1)
        .animation(.easeOut(duration: 0.4).delay(round ? 0 : 0.3), value: round)
    }
    .frame(width: w, height: h)
    .clipShape(Capsule())
    .modifier(GlassCapsule(look: glassLook, rim: contrast == .increased ? 2 : 1.5))
    .overlay(Capsule().fill(.white.opacity(seal)).allowsHitTesting(false))  // the glass lights up as it starts
    .overlay {
      if model.stage == .armed && !reduceMotion { Sweep() }
    }
    .background {
      if model.stage == .alarm {  // a ring that pulses with the beep
        Capsule()
          .fill(Color(red: 1, green: 80 / 255, blue: 88 / 255).opacity(0.18 * pulse))
          .padding(-10 * pulse)
      }
    }
    .animation(Theme.motion(Theme.glass, reduced: reduceMotion), value: model.stage)
    .modifier(Shake(model.flinch, amount: reduceMotion ? 0 : 12))  // touched: it flinches (audit C4)
    .animation(.timingCurve(0.36, 0.07, 0.19, 0.97, duration: 0.46), value: model.flinch)
    .scaleEffect(appeared ? 1 : 0.92)
    .opacity(appeared ? 1 : 0)
    .onAppear {
      withAnimation(Theme.motion(Theme.out(0.5), reduced: reduceMotion)) { appeared = true }
    }
  }

  /// The shock wave leaving the ring's rim as guarding starts (audit C3).
  private var shockRing: some View {
    Circle()
      .strokeBorder(.white.opacity(0.75), lineWidth: 2)
      .background(Circle().strokeBorder(Theme.amber.opacity(0.35), lineWidth: 10).blur(radius: 6))
      .shadow(color: Theme.amber.opacity(0.55), radius: 17)
      .frame(width: 212, height: 212)
      .scaleEffect(shockScale)
      .opacity(shockOpacity)
      .allowsHitTesting(false)
  }

  private func shockwave() {
    guard !reduceMotion else { return }
    replay(.timingCurve(0.15, 0.6, 0.3, 1, duration: 0.8)) { go in
      shockScale = go ? 2.5 : 1
      shockOpacity = go ? 0 : 0.95
    }
    replay(Theme.out(0.5)) { go in seal = go ? 0 : 0.28 }
  }

  private var glassLook: GlassCapsule.Look {
    switch model.stage {
    case .alarm: .alarm
    case .welcome: .dark
    default: .clear
    }
  }

  private var icon: ShieldGlyph.Look {
    switch model.stage {
    case .alarm: .alarm
    case .welcome: .clear
    default: .guarding
    }
  }

  private var title: String {
    switch model.stage {
    case .alarm: L("Alarm raised")
    case .welcome: model.welcome.title
    default: L("Please don't touch")
    }
  }

  private var sub: String {
    switch model.stage {
    case .alarm: return alarmLine
    case .welcome: return model.welcome.sub
    default: return L("This Mac is guarded. Touching it sounds the alarm.")
    }
  }

  // Only what is true right now (audit H4).
  private var alarmLine: String {
    if model.recording && model.pushOn { return L("You're on camera. The owner has been notified.") }
    if model.recording { return L("You're on camera.") }
    if model.pushOn { return L("The owner has been notified.") }
    return L("Please put it back.")
  }

  private var chips: some View {
    let stage = model.stage
    let shown = stage == .armed || stage == .alarm || stage == .welcome
    return HStack(spacing: 12) {
      switch stage {
      case .armed:
        if model.recording {
          Chip(dot: .green, text: L("Walking by isn't recorded. Touching it is."))
        } else {
          Chip(dot: .gray, text: L("Not recording this time"))
        }
        if !model.note.isEmpty {
          Chip(dot: nil, text: "“\(model.note)” · \(Clock.time.string(from: model.armedAt))")
        }
      case .alarm:
        if model.recording { Chip(dot: .recording(pulse), text: L("Recording")) }
      case .welcome:
        ForEach(model.welcome.chips, id: \.self) { Chip(dot: nil, text: $0, dark: true) }
      default:
        EmptyView()
      }
    }
    .opacity(shown ? 1 : 0)
    .offset(y: shown ? 0 : 8)
    .animation(.spring(duration: 0.4, bounce: 0.3).delay(shown ? 0.42 : 0), value: stage)
  }

  /// No second number under the ring (audit C1): the keys say how to stop it.
  private var countdownText: some View {
    VStack(spacing: 12) {
      Text(L("Leave it lying still and walk away"))
        .font(.system(size: 26, weight: .semibold))
      HStack(spacing: 8) {
        Keycap(dark: true) {
          Text(verbatim: "esc")
            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
        }
        Text(L("cancels"))
        Text(verbatim: "·")
          .opacity(0.5)
        Keycap(dark: true) {
          Image(systemName: "touchid")
            .font(.system(size: 15))
        }
        Text(L("or rest a finger on Touch ID"))
      }
      .font(.system(size: 15))
      .foregroundStyle(.white.opacity(0.74))
      if model.test {
        Text(L("Test mode: this run stays silent"))
          .font(.system(size: 14))
          .foregroundStyle(Theme.amberHi)
      }
    }
    .foregroundStyle(.white)
    .fixedSize()
  }

  /// For whoever does not read the notice's language: English under Chinese, Chinese under English.
  private var foot: some View {
    Text(L("PLEASE DO NOT TOUCH · PASSING BY IS NOT RECORDED"))
      .font(.system(size: 13))
      .tracking(3.4)
      .foregroundStyle(.white.opacity(0.58))
      .fixedSize()
  }

  /// Striped like the test-mode switch, so a test run never looks like the real thing (audit C8).
  private var testTag: some View {
    Text(L("Test · silent"))
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(Theme.ink)
      .padding(.horizontal, 13)
      .frame(height: 30)
      .background {
        ZStack {
          Capsule().fill(Theme.amberDeep)
          Stripes(band: 6).clipShape(Capsule())
        }
      }
      .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
      .fixedSize()
  }
}

/// Back to the menu bar: x eases in and y eases out, so the notice rises and then swings into the
/// shield along an arc, shrinking as it goes (audit C5). With Reduce Motion it only fades.
private struct Flight: ViewModifier {
  let leaving: Bool
  let anchor: UnitPoint
  let offset: CGSize
  let still: Bool

  @ViewBuilder func body(content: Content) -> some View {
    if still {
      content
        .opacity(leaving ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: leaving)
    } else {
      content
        .scaleEffect(leaving ? 0.05 : 1, anchor: anchor)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.75), value: leaving)
        .opacity(leaving ? 0 : 1)
        .animation(.linear(duration: 0.28).delay(0.47), value: leaving)
        .offset(y: leaving ? offset.height : 0)
        .animation(.timingCurve(0.2, 0.75, 0.35, 1, duration: 0.75), value: leaving)
        .offset(x: leaving ? offset.width : 0)
        .animation(.timingCurve(0.55, 0, 0.75, 0.35, duration: 0.75), value: leaving)
    }
  }
}

private struct SignLabel: View {
  let icon: ShieldGlyph.Look
  let title: String
  let sub: String
  let breathing: Bool
  @State private var inhaled = false

  private static let titleFont = NSFont.systemFont(ofSize: 56, weight: .semibold)
  private static let subFont = NSFont.systemFont(ofSize: 19)

  /// The capsule's width for these lines: 34 + icon 84 + 26 + text + 44, as in design A.
  static func width(title: String, sub: String) -> CGFloat {
    let t = (title as NSString).size(withAttributes: [.font: titleFont]).width
    let s = (sub as NSString).size(withAttributes: [.font: subFont]).width
    return ceil(34 + 84 + 26 + max(t, s) + 44 + 4)
  }

  var body: some View {
    HStack(spacing: 26) {
      ZStack {
        Circle().fill(.white.opacity(0.12))
        Circle().strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
        ShieldGlyph(look: icon, drawsTick: icon == .clear)  // back: the tick draws itself in
          .frame(width: 44, height: 44)
          .scaleEffect(inhaled ? 1.06 : 1)
          .opacity(inhaled ? 0.86 : 1)
      }
      .frame(width: 84, height: 84)
      VStack(alignment: .leading, spacing: 8) {
        Text(title)
          .font(.system(size: 56, weight: .semibold))
          .shadow(color: .black.opacity(0.22), radius: 9, y: 2)
        Text(sub)
          .font(.system(size: 19))
          .foregroundStyle(.white.opacity(0.8))
      }
      .lineLimit(1)
    }
    .padding(.leading, 34)
    .padding(.trailing, 44)
    .foregroundStyle(.white)
    .onAppear { breathe(breathing) }
    .onChange(of: breathing) { _, on in breathe(on) }
  }

  private func breathe(_ on: Bool) {
    if on {
      withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) { inhaled = true }
    } else {
      withAnimation(.easeOut(duration: 0.3)) { inhaled = false }
    }
  }
}

/// The ring: a faint track, the amber arc brightening toward its head, a glowing head, and the white
/// flash as guarding starts (audit C2). Drawn from the clock, so it never drifts from the digits; on
/// a cancel it unwinds the way it came (audit C6).
private struct CountdownRing: View {
  @ObservedObject var model: VeilModel

  var body: some View {
    TimelineView(.animation) { tl in
      let p = progress(at: tl.date)
      let lit = flash(at: tl.date)
      Canvas { ctx, size in
        CountdownRing.draw(&ctx, size, p, lit)
      }
    }
    .frame(width: 212, height: 212)
  }

  private func progress(at now: Date) -> Double {
    if model.cancelling {
      let q = min(1, now.timeIntervalSince(model.unwindAt) / 0.45)
      return model.unwindFrom * (1 - Ease.retreat(q))
    }
    guard model.stage == .countdown else { return 1 }
    return min(1, max(0, now.timeIntervalSince(model.countdownFrom) / max(model.countdownSeconds, 0.1)))
  }

  private func flash(at now: Date) -> Double {
    let q = now.timeIntervalSince(model.shockAt) / 0.38
    return q >= 0 && q < 1 ? 1 - q : 0
  }

  static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ p: Double, _ flash: Double) {
    let c = CGPoint(x: size.width / 2, y: size.height / 2)
    let r = 91.5
    func arc(_ a0: Double, _ a1: Double) -> Path {
      var path = Path()
      path.addArc(center: c, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: false)
      return path
    }
    func point(_ a: Double) -> CGPoint { CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)) }
    let circle = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.stroke(circle, with: .color(.white.opacity(0.16)), lineWidth: 5)
    if p > 0.002 {
      let a0 = -Double.pi / 2, a1 = a0 + 2 * .pi * p
      ctx.stroke(arc(a0, a1), with: .color(Theme.amber), style: StrokeStyle(lineWidth: 5, lineCap: .round))
      // The last half radian brightens toward white; over so short an arc the chord's gradient
      // matches the conic one.
      let span = min(0.55, a1 - a0)
      if span > 0.02 {
        let cream = Color(red: 1, green: 242 / 255, blue: 214 / 255)
        ctx.stroke(arc(a1 - span, a1),
                   with: .linearGradient(Gradient(colors: [cream.opacity(0), cream.opacity(0.95)]), startPoint: point(a1 - span), endPoint: point(a1)),
                   style: StrokeStyle(lineWidth: 5, lineCap: .butt))
      }
      var glow = ctx
      glow.addFilter(.shadow(color: Color(red: 1, green: 196 / 255, blue: 100 / 255).opacity(0.95), radius: 5))
      let head = point(a1)
      glow.fill(Path(ellipseIn: CGRect(x: head.x - 3.4, y: head.y - 3.4, width: 6.8, height: 6.8)), with: .color(.white))
    }
    if flash > 0 {
      ctx.stroke(circle, with: .color(.white.opacity(flash)), lineWidth: 5 + 4 * flash)
    }
  }
}

/// The countdown's number: each second rises in from below and sharpens as the last one leaves
/// upward (audit C1).
private struct Digits: View {
  let value: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Text(verbatim: "\(value)")
        .font(.system(size: 92, weight: .thin, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.white)
        .id(value)
        .transition(shift)
    }
    .frame(width: 140, height: 120)
    .animation(Theme.out(0.55), value: value)
  }

  private var shift: AnyTransition {
    guard !reduceMotion else { return .opacity }
    return .asymmetric(
      insertion: AnyTransition.modifier(active: DigitShift(y: 50), identity: DigitShift(y: 0))
        .animation(.timingCurve(0.22, 0.9, 0.3, 1, duration: 0.55)),
      removal: AnyTransition.modifier(active: DigitShift(y: -50), identity: DigitShift(y: 0))
        .animation(.timingCurve(0.5, 0, 0.9, 0.5, duration: 0.32)))
  }
}

/// A digit on its way in or out: 42 % of its box away, a little smaller, blurred and clear.
private struct DigitShift: ViewModifier {
  let y: CGFloat

  func body(content: Content) -> some View {
    let away = y != 0
    return content
      .offset(y: y)
      .scaleEffect(away ? 0.9 : 1)
      .blur(radius: away ? 10 : 0)
      .opacity(away ? 0 : 1)
  }
}

/// A highlight crossing the notice once every 8 s: a still screen looks frozen, a breathing one looks watched.
private struct Sweep: View {
  @State private var go = false

  var body: some View {
    GeometryReader { g in
      LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.26), location: 0.45),
                             .init(color: .white.opacity(0.06), location: 0.55), .init(color: .clear, location: 1)],
                     startPoint: .leading, endPoint: .trailing)
        .frame(width: g.size.width * 0.6, height: g.size.height)
        .offset(x: go ? g.size.width * 7.2 : -g.size.width * 0.8)
    }
    .clipShape(Capsule())
    .allowsHitTesting(false)
    .onAppear {
      withAnimation(.linear(duration: 8).repeatForever(autoreverses: false).delay(1.2)) { go = true }
    }
  }
}

private struct Chip: View {
  enum Dot { case green, gray, recording(Double) }
  let dot: Dot?
  let text: String
  var dark = false

  var body: some View {
    HStack(spacing: 10) {
      if let dot { dotView(dot) }
      Text(text)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white.opacity(0.92))
    }
    .padding(.horizontal, 18)
    .frame(height: 40)
    .background {
      if dark {  // on the bare desktop after the fog clears: it brings its own blur
        ZStack {
          Capsule().fill(.ultraThinMaterial)
          Capsule().fill(Color(red: 22 / 255, green: 26 / 255, blue: 38 / 255).opacity(0.58))
        }
      } else {  // on the frost, which is already blurred: a light wash, as in design A
        Capsule().fill(Color.white.opacity(0.1))
      }
    }
    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
    .fixedSize()
  }

  @ViewBuilder private func dotView(_ dot: Dot) -> some View {
    switch dot {
    case .green:  // the camera light's color: it answers the question the light raises
      Circle()
        .fill(Theme.camera)
        .frame(width: 9, height: 9)
        .shadow(color: Theme.camera.opacity(0.8), radius: 4)
    case .gray:
      Circle().fill(.white.opacity(0.4)).frame(width: 9, height: 9)
    case .recording(let pulse):
      Circle()
        .fill(Color(red: 1, green: 0x45 / 255, blue: 0x50 / 255))
        .frame(width: 9, height: 9)
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
        .shadow(color: Color(red: 1, green: 0x45 / 255, blue: 0x50 / 255).opacity(0.9), radius: 5)
        .opacity(0.4 + 0.6 * pulse)
    }
  }
}

/// Liquid Glass on macOS 26; on macOS 14 and 15, a thin material with the same highlight rim. Over
/// the frost the glass is the clear kind, lit by design A's white (or red) wash, so the sign reads as
/// a brighter lens on the fog rather than a dark pill. Welcome back sits on the bare desktop and
/// keeps the regular glass, which blurs what is behind it.
private struct GlassCapsule: ViewModifier {
  enum Look { case clear, alarm, dark }
  let look: Look
  let rim: CGFloat

  @ViewBuilder func body(content: Content) -> some View {
    #if compiler(>=6.2)
    if #available(macOS 26, *) {
      content
        .background(Capsule().fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom)))
        .glassEffect(look == .dark ? Glass.regular : Glass.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(rimGradient, lineWidth: rim - 0.5))
    } else {
      frosted(content)
    }
    #else
    frosted(content)
    #endif
  }

  private var fill: [Color] {
    switch look {
    case .clear: [.white.opacity(0.17), .white.opacity(0.05)]
    case .alarm: [Color(red: 1, green: 96 / 255, blue: 100 / 255).opacity(0.42), Color(red: 196 / 255, green: 24 / 255, blue: 40 / 255).opacity(0.3)]
    case .dark: [Color(red: 34 / 255, green: 39 / 255, blue: 54 / 255).opacity(0.66), Color(red: 18 / 255, green: 21 / 255, blue: 31 / 255).opacity(0.6)]
    }
  }

  private var rimGradient: LinearGradient {
    LinearGradient(stops: [.init(color: .white.opacity(0.9), location: 0), .init(color: .white.opacity(0.2), location: 0.36),
                           .init(color: .white.opacity(0.05), location: 0.62), .init(color: .white.opacity(0.55), location: 1)],
                   startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  private func frosted(_ content: Content) -> some View {
    content
      .background {
        ZStack {
          Capsule().fill(.ultraThinMaterial)
          Capsule().fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
        }
      }
      .overlay(Capsule().strokeBorder(rimGradient, lineWidth: rim))
      .shadow(color: .black.opacity(0.36), radius: 35, y: 26)
  }
}
