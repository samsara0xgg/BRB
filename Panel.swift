import AppKit
import AVFoundation
import Carbon
import CoreImage.CIFilterBuiltins
import LocalAuthentication
import SwiftUI

/// The menu-bar panel holds only what matters before stepping away (audit A1): the start button,
/// where the Mac is, a note for the screen and the last few sessions, with what is on in the ⋯
/// menu. Anything missing is listed on top and fixed in place (A2); everything else lives in Settings.
final class Panel: NSObject, NSPopoverDelegate {
  let model: PanelModel
  /// The menu-bar button the panel hangs from.
  var anchor: () -> NSStatusBarButton? = { nil }
  private let popover = NSPopover()
  private var monitor: Any?
  private var poll: Timer?

  init(model: PanelModel = PanelModel()) {
    self.model = model
    super.init()
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
    let host = NSHostingController(rootView: PanelView(model: model))
    host.sizingOptions = .preferredContentSize
    popover.contentViewController = host
    model.onClose = { [weak self] in self?.close() }
  }

  var isShown: Bool { popover.isShown }

  func toggle() {
    if popover.isShown { close() } else { show() }
  }

  /// `intro`: the three cards, from Settings' "Show again".
  func show(intro: Bool = false) {
    guard anchor() != nil else { return }
    if intro || !Prefs.introSeen {
      model.introStep = 0
      model.introForward = true
      model.page = .intro
    } else if !popover.isShown {
      model.page = .main
    }
    model.opened()
    NSApp.activate(ignoringOtherApps: true)  // an accessory app's text field needs this for typing
    present()
  }

  /// Hangs the panel from the shield. Right after launch the menu bar may not have placed the
  /// shield yet, and the panel would hang from the corner of the screen: it waits, 2 s at most.
  private func present(tries: Int = 0) {
    guard let button = anchor() else { return }
    if tries < 8, let bar = button.window, let screen = bar.screen ?? NSScreen.main, bar.frame.maxY < screen.frame.midY {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.present(tries: tries + 1) }
      return
    }
    // Light or dark as the system is set, like Control Center: left alone, a popover takes the menu
    // bar's look, which follows the wallpaper.
    popover.appearance = NSApp.effectiveAppearance
    if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    guard let window = popover.contentViewController?.view.window else { return }
    window.makeKey()
    // The note field waits for a click instead of taking the keys: ↩ starts, ← → change the place.
    window.makeFirstResponder(nil)
    DispatchQueue.main.async { window.makeFirstResponder(nil) }
    start()
  }

  func close() {
    if popover.isShown { popover.performClose(nil) }
  }

  func popoverDidClose(_ notification: Notification) {
    stop()
    model.optionHeld = false
  }

  /// While shown: the checks once a second, so a fix made in System Settings ticks off by itself
  /// (audit B8), and the keys: ⌥ for a silent run, ← → for the place or the intro's cards.
  private func start() {
    stop()
    let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.model.poll() }
    RunLoop.main.add(t, forMode: .common)
    poll = t
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
      guard let self, event.window === popover.contentViewController?.view.window else { return event }
      return handle(event) ? nil : event
    }
  }

  private func stop() {
    poll?.invalidate()
    poll = nil
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }

  private func handle(_ event: NSEvent) -> Bool {
    if event.type == .flagsChanged {
      let held = event.modifierFlags.contains(.option)
      if model.optionHeld != held { model.optionHeld = held }
      return false
    }
    guard !(event.window?.firstResponder is NSText),
          event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
    switch event.keyCode {
    case 123: return model.step(-1)
    case 124: return model.step(1)
    default: return false
    }
  }
}

/// One line of the readiness list.
struct Check: Identifiable, Equatable {
  enum ID: String { case accessibility, camera, sleep, speakers, touchID, push, secureInput, lock }
  let id: ID
  let title: String
  let detail: String
  let ok: Bool
  var optional = false
  /// Shown only when it fails: something that is almost always fine.
  var quiet = false
  /// For the camera: never asked yet, so "Allow" rather than "Open Settings".
  var askable = false

  var shown: Bool { !quiet || !ok }
}

/// What arming needs, checked without side effects. The sudo check runs off the main thread (audit
/// L5); `sleep` passes on what it said last time, for the checks that run every second.
enum Preflight {
  /// What the checks are read from: all fine unless said otherwise, for the snapshot command.
  struct Facts {
    var trusted = true
    var camera = AVAuthorizationStatus.authorized
    var hasCamera = true
    var speakers = true
    var touchID = true
    var secureInput = false
    var lock = true
    var sleep = true
    var push = true
  }

  static func run(sleep known: Bool? = nil, _ done: @escaping ([Check]) -> Void) {
    let trusted = AXIsProcessTrusted()
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    let camera = Recorder.camera != nil
    let speakers = Alarm.builtInSpeakers() != nil
    var error: NSError?
    let touchID = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    let secure = IsSecureEventInputEnabled()
    let lock = GuardApp.lockScreen != nil
    let push = Prefs.phonePaired
    DispatchQueue.global(qos: .userInitiated).async {
      let sleep = known ?? sleepRuleInstalled()
      DispatchQueue.main.async {
        done(checks(Facts(trusted: trusted, camera: status, hasCamera: camera, speakers: speakers, touchID: touchID,
                          secureInput: secure, lock: lock, sleep: sleep, push: push)))
      }
    }
  }

  static func checks(_ f: Facts) -> [Check] {
    [
      Check(id: .accessibility, title: L("Accessibility"),
            detail: f.trusted ? L("Notices the keyboard and trackpad") : L("Needed to notice the keyboard and trackpad"), ok: f.trusted),
      Check(id: .camera, title: L("Camera"),
            detail: !f.hasCamera ? L("No built-in camera: an alarm won't be recorded")
              : f.camera == .authorized ? L("Films only around an alarm")
              : f.camera == .notDetermined ? L("Allow it so an alarm can be recorded") : L("Turned off for Back in 5 in System Settings"),
            ok: f.hasCamera && f.camera == .authorized, optional: !f.hasCamera, askable: f.hasCamera && f.camera == .notDetermined),
      Check(id: .sleep, title: L("Stay awake with the lid shut"),
            detail: f.sleep ? L("Keeps guarding with the lid closed") : L("Needs an admin rule, installed once with your password"), ok: f.sleep),
      Check(id: .speakers, title: L("Speakers"),
            detail: f.speakers ? L("The siren plays on the built-in speakers") : L("No built-in speakers found"), ok: f.speakers),
      Check(id: .touchID, title: L("Touch ID"),
            detail: f.touchID ? L("Rest a finger to stop guarding") : L("Unlock the Mac to stop guarding instead"), ok: f.touchID, optional: true),
      Check(id: .push, title: L("Phone alerts"),
            detail: f.push ? L("Alarms reach your phone") : L("Off: alarms stay on this Mac"), ok: f.push, optional: true),
      Check(id: .secureInput, title: L("Secure keyboard entry"),
            detail: f.secureInput ? L("A password field or Terminal's Secure Keyboard Entry is on, so keys would slip past. Close it first.") : L("Not on"),
            ok: !f.secureInput, quiet: true),
      Check(id: .lock, title: L("Lock screen"),
            detail: f.lock ? L("Locks the screen during an alarm") : L("The system's lock function is unavailable"), ok: f.lock, quiet: true),
    ]
  }

  /// Asks sudo whether the rule is there, without running pmset (so nothing changes).
  static func sleepRuleInstalled() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    p.arguments = ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
  }

  /// The AppleScript that installs the rule behind the system's password prompt, so nobody needs
  /// Terminal. `admin: false` leaves the prompt out, for a caller that is already root (CI).
  static func sleepRuleScript(user: String, admin: Bool = true) -> String? {
    guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return nil }
    let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
    let sh = "t=$(/usr/bin/mktemp) && printf '%s\\n' '\(rule)' > \"$t\" && /usr/sbin/visudo -cf \"$t\" > /dev/null"
      + " && /usr/bin/install -m 0440 -o root -g wheel \"$t\" /etc/sudoers.d/brb && rm -f \"$t\" /etc/sudoers.d/guard-mode"
    func quoted(_ s: String) -> String {
      "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    let prompt = admin ? " with prompt " + quoted(L("Back in 5 keeps the Mac awake with the lid shut while it guards.")) + " with administrator privileges" : ""
    return "do shell script " + quoted(sh) + prompt
  }

  static func installSleepRule(user: String = NSUserName(), admin: Bool = true, _ done: @escaping (Bool) -> Void) {
    guard let script = sleepRuleScript(user: user, admin: admin) else { return done(false) }
    DispatchQueue.global(qos: .userInitiated).async {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      p.arguments = ["-e", script]
      p.standardOutput = FileHandle.nullDevice
      var ok = false
      if (try? p.run()) != nil {
        p.waitUntilExit()
        ok = p.terminationStatus == 0
      }
      log("lid rule \(ok ? "installed" : "not installed")")
      DispatchQueue.main.async { done(ok) }
    }
  }
}

/// A recording on disk, and the session it belongs to when the history still has it.
struct Clip: Identifiable {
  let url: URL
  let date: Date
  let session: Session?
  var bytes: Int64 = 0
  var id: URL { url }
}

/// What the panel and the Settings window show. One model for both, so they never disagree.
final class PanelModel: ObservableObject {
  enum Page { case intro, main }
  @Published var page = Page.main
  @Published var introStep = 0
  /// Which way the intro's cards move: set just before the step changes.
  @Published var introForward = true
  @Published var phase = GuardApp.Phase.idle
  @Published var checks: [Check] = []
  /// The "Before guarding" card: what was missing, each row ticked off and folded away (audit A2).
  @Published var fixRows: [Check] = []
  @Published var setupTotal = 0
  @Published var checking = false
  @Published var place = Prefs.place { didSet { if !canned { Prefs.place = place } } }
  /// Cut at the limit, never silently: the field shakes instead (audit B2).
  @Published var note = Prefs.note {
    didSet {
      if note.count > Prefs.noteLimit {
        note = String(note.prefix(Prefs.noteLimit))
        noteBump += 1
      }
      if !canned { Prefs.note = note }
    }
  }
  @Published var noteBump = 0
  /// The start button was pressed with something missing: it shakes and the card lights up.
  @Published var lockedNudge = 0
  /// The setup card folded away: the start button lights up.
  @Published var bloom = 0
  /// ⌥ held: a silent run, this once (audit A5).
  @Published var optionHeld = false
  @Published var volume = Double(Alarm.loudVolume * 100) { didSet { if !canned { Alarm.loudVolume = Float32(volume / 100) } } }
  @Published var testMode = Prefs.testMode { didSet { if !canned { Prefs.testMode = testMode } } }
  @Published var veil = Prefs.veil { didSet { if !canned { Prefs.veil = veil } } }
  /// A paired iPhone gets the alarms.
  @Published var pushOn = Prefs.phonePaired
  @Published var history: [Session] = []
  @Published var clips: [Clip] = []
  /// Real alarms that ended after this are new to the owner: "New" on their row.
  @Published var newSince = Date.distantFuture
  /// The countdown, for the panel when the frosted screen is off.
  @Published var remaining = 5
  @Published var countdownFrom = Date()
  @Published var copied: String?
  @Published var installing = false
  @Published var confirmReset = false
  @Published var linkReset = false
  @Published var liveLink = Live.link.absoluteString
  @Published var previewing = false
  /// The line under the volume that says what "Preview…" is about to play.
  @Published var confirmPreview = false
  @Published var previewAt = Date.distantPast
  @Published var settingsTab = SettingsTab.general
  /// The iPhone app's pairing code, for Settings → Phone.
  let pairing = PairingModel()

  /// `true`: a silent run this once.
  var onArm: (Bool) -> Void = { _ in }
  var onCancel: () -> Void = {}
  var onClose: () -> Void = {}
  /// A fix made outside BRB landed: show the panel again so the row ticks off in view.
  var onReopen: () -> Void = {}
  var onSettings: (SettingsTab) -> Void = { _ in }
  var onIntro: () -> Void = {}
  /// The panel showed the alarms: the menu-bar shield drops its red dot.
  var onSeen: () -> Void = {}
  /// New results of the checks: a paired iPhone is told what works.
  var onChecks: ([Check]) -> Void = { _ in }
  /// The snapshot command's: it shows what it was given, never this Mac's checks or history.
  let canned: Bool
  private var sleepRule: Bool?
  private var folds: Set<Check.ID> = []
  private var awaiting: Timer?
  private var resetAsk = 0
  private var previewAsk = 0

  init(canned: Bool = false) {
    self.canned = canned
    if !canned { refreshChecks() }
  }

  var toFix: Int { checks.filter { !$0.ok && !$0.optional }.count }
  var ready: Bool { !checks.isEmpty && toFix == 0 }
  /// Something is missing: the start button is a quiet well that says what to do first.
  var locked: Bool { toFix > 0 }
  var setupDone: Int { setupTotal - fixRows.filter { !$0.ok }.count }

  func check(_ id: Check.ID) -> Check? { checks.first { $0.id == id } }

  /// What is on, for the status chip's tooltip. Read-only: only "Settings…" opens Settings
  /// (Allen, 2026-10-14).
  var statusRows: [(symbol: String, title: String, on: Bool)] {
    [("video", L("Camera"), check(.camera)?.ok == true),
     ("iphone", L("Phone alerts"), pushOn),
     ("laptopcomputer", L("Stay awake with the lid shut"), check(.sleep)?.ok == true),
     ("touchid", L("Touch ID"), check(.touchID)?.ok == true)]
  }

  func isNew(_ s: Session) -> Bool { s.alarmed && !s.test && s.ended > newSince }

  /// The panel opened: what it shows now is not new any more afterwards.
  func opened() {
    guard !canned else { return }
    newSince = Prefs.alarmsSeenAt
    Prefs.alarmsSeenAt = Date()
    onSeen()
    refresh()
  }

  func refresh() {
    guard !canned else { return }
    place = Prefs.place
    note = Prefs.note
    volume = Double(Alarm.loudVolume * 100)
    testMode = Prefs.testMode
    veil = Prefs.veil
    pushOn = Prefs.phonePaired
    history = History.load()
    clips = PanelModel.clips(history)
    liveLink = Live.link.absoluteString
    copied = nil
    confirmReset = false
    confirmPreview = false
    refreshChecks()
  }

  static func clips(_ history: [Session]) -> [Clip] {
    let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
    let files = (try? FileManager.default.contentsOfDirectory(at: Recorder.folder, includingPropertiesForKeys: Array(keys))) ?? []
    return files.filter { $0.pathExtension == "mov" }
      .map { url -> Clip in
        let values = try? url.resourceValues(forKeys: keys)
        return Clip(url: url, date: values?.contentModificationDate ?? .distantPast,
                    session: history.first { $0.clip == url.lastPathComponent }, bytes: Int64(values?.fileSize ?? 0))
      }
      .sorted { $0.date > $1.date }
  }

  /// Everything, the admin rule included (sudo, so not every second).
  func refreshChecks(_ done: (() -> Void)? = nil) {
    checking = true
    Preflight.run { [weak self] checks in
      guard let self else { return }
      checking = false
      sleepRule = checks.first { $0.id == .sleep }?.ok
      apply(checks)
      done?()
    }
  }

  /// Once a second while the panel or Settings shows.
  func poll() {
    guard !canned else { return }
    Preflight.run(sleep: sleepRule) { [weak self] in self?.apply($0) }
  }

  /// Settings' "Check again": the spinner stays long enough to be seen.
  func checkAgain() {
    checking = true
    let start = Date()
    Preflight.run { [weak self] checks in
      guard let self else { return }
      sleepRule = checks.first { $0.id == .sleep }?.ok
      apply(checks)
      DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.6 - Date().timeIntervalSince(start))) { [weak self] in
        self?.checking = false
      }
    }
  }

  /// New results: the card keeps the rows it listed, so a fixed one ticks, says what it does now and
  /// folds away 0.95 s later; the last one takes the card with it.
  func apply(_ new: [Check]) {
    onChecks(new)
    let first = checks.isEmpty
    checks = new
    var rows = fixRows.map { row in new.first { $0.id == row.id } ?? row }
    let added = new.filter { c in c.shown && !c.ok && !c.optional && !rows.contains { $0.id == c.id } }
    rows += added
    let order = new.map(\.id)
    rows.sort { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
    if fixRows.isEmpty { setupTotal = 0 }
    setupTotal += added.count
    if rows != fixRows {
      if first || page != .main {
        fixRows = rows
      } else {
        withAnimation(Theme.resize) { fixRows = rows }
      }
    }
    for row in rows where row.ok && !folds.contains(row.id) {
      folds.insert(row.id)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in self?.fold(row.id) }
    }
  }

  private func fold(_ id: Check.ID) {
    folds.remove(id)
    guard let i = fixRows.firstIndex(where: { $0.id == id }), fixRows[i].ok else { return }
    withAnimation(Theme.out(0.42)) { _ = fixRows.remove(at: i) }
    guard fixRows.isEmpty else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.44) { [weak self] in
      guard let self, fixRows.isEmpty else { return }
      setupTotal = 0
      bloom += 1
    }
  }

  func arm() {
    guard phase == .idle else { return }
    guard !checks.isEmpty else {
      refreshChecks { [weak self] in self?.arm() }
      return
    }
    guard ready else {
      lockedNudge += 1
      return
    }
    let silentOnce = optionHeld && !testMode
    if veil { onClose() }  // without the frosted screen the panel shows the countdown (audit A8)
    onArm(silentOnce)
  }

  func showIntro() {
    introStep = 0
    introForward = true
    withAnimation(Theme.resize) { page = .intro }
  }

  func goIntro(_ i: Int) {
    guard i != introStep, (0..<3).contains(i) else { return }
    introForward = i > introStep
    DispatchQueue.main.async { [weak self] in  // the cards read the direction before they move
      withAnimation(Theme.slide) { self?.introStep = i }
    }
  }

  /// ← and →: the intro's cards, or the place.
  func step(_ d: Int) -> Bool {
    if page == .intro {
      let n = introStep + d
      guard (0..<3).contains(n) else { return false }
      goIntro(n)
      return true
    }
    guard phase == .idle else { return false }
    let all = Place.allCases
    let i = all.firstIndex(of: place) ?? 0
    place = all[(i + d + all.count) % all.count]
    return true
  }

  /// The end of the introduction: either straight to a silent first run, or to the panel.
  func finishIntro(tryIt: Bool) {
    Prefs.introSeen = true
    withAnimation(Theme.resize) { page = .main }
    guard tryIt else { return }
    testMode = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.arm() }
  }

  func fix(_ check: Check) {
    switch check.id {
    case .accessibility:
      // The prompt also puts BRB in the list; the panel comes back once the switch is on.
      _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
      open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
      onClose()
      awaitGrant { AXIsProcessTrusted() }
    case .camera:
      if check.askable {
        AVCaptureDevice.requestAccess(for: .video) { granted in
          DispatchQueue.main.async {
            self.poll()
            if granted { self.onReopen() }
          }
        }
      } else {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
        onClose()
        awaitGrant { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
      }
    case .sleep:
      installing = true
      Preflight.installSleepRule { [weak self] ok in
        guard let self else { return }
        installing = false
        if ok {
          sleepRule = true
          onReopen()
        }
        refreshChecks()
      }
    case .push:
      onSettings(.phone)
    default:
      refreshChecks()
    }
  }

  /// Watches for a permission granted in System Settings, for three minutes at most.
  private func awaitGrant(_ granted: @escaping () -> Bool) {
    awaiting?.invalidate()
    let start = Date()
    let t = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      if granted() {
        timer.invalidate()
        awaiting = nil
        onReopen()
      } else if Date().timeIntervalSince(start) > 180 {
        timer.invalidate()
        awaiting = nil
      }
    }
    RunLoop.main.add(t, forMode: .common)
    awaiting = t
  }

  func copy(_ text: String, as what: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    copied = what
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
      if self?.copied == what { self?.copied = nil }
    }
  }

  /// "Reset link…" opens a line that says what happens; nobody answering folds it back after 5 s
  /// (audit B3).
  func askReset() {
    withAnimation(Theme.out(0.3)) { confirmReset = true }
    resetAsk += 1
    let ask = resetAsk
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let self, confirmReset, resetAsk == ask else { return }
      withAnimation(Theme.out(0.3)) { self.confirmReset = false }
    }
  }

  func cancelReset() {
    withAnimation(Theme.out(0.3)) { confirmReset = false }
  }

  func resetLink() {
    Live.resetLink()
    withAnimation(Theme.out(0.3)) {
      confirmReset = false
      liveLink = Live.link.absoluteString
      linkReset = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
      withAnimation(.easeOut(duration: 0.3)) { self?.linkReset = false }
    }
  }

  /// "Preview…" first says what will sound, how loud and that headphones don't stop it; nobody
  /// answering folds it back after 8 s. A preview that just plays out of nowhere is startling.
  func askPreview() {
    guard phase == .idle, !previewing else { return }
    withAnimation(Theme.out(0.3)) { confirmPreview = true }
    previewAsk += 1
    let ask = previewAsk
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
      guard let self, confirmPreview, previewAsk == ask else { return }
      withAnimation(Theme.out(0.3)) { self.confirmPreview = false }
    }
  }

  func cancelPreview() {
    withAnimation(Theme.out(0.3)) { confirmPreview = false }
  }

  /// 0.6 s of the siren at the set volume (audit B4), once confirmed.
  func preview() {
    withAnimation(Theme.out(0.3)) { confirmPreview = false }
    guard phase == .idle, !previewing else { return }
    previewing = true
    previewAt = Date()
    Alarm.preview()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in self?.previewing = false }
  }

  /// A recording selected in Finder (audit A6, A7); without one, the folder.
  func reveal(_ clip: String?) {
    let url = clip.map { Recorder.folder.appendingPathComponent($0) }
    if let url, FileManager.default.fileExists(atPath: url.path) {
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } else {
      try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
      NSWorkspace.shared.open(Recorder.folder)
    }
    onClose()
  }

  func open(_ url: String) {
    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
  }
}

// MARK: - views

struct PanelView: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    Group {
      switch model.page {
      case .intro: IntroPage(model: model).transition(.opacity)
      case .main: MainPage(model: model).transition(.opacity)
      }
    }
    .padding(14)
    .frame(width: 340)
    .background(alignment: .top) { Glow(lit: model.page == .main && model.phase == .idle && model.ready && model.fixRows.isEmpty) }
  }
}

/// A warm light behind the start button while it is ready. It comes on as the setup card folds
/// away, with the light crossing the button, and goes while something is missing.
private struct Glow: View {
  let lit: Bool

  var body: some View {
    // Centered on the start button; the ellipse is the frame's shape, wider than tall.
    EllipticalGradient(colors: [Theme.glow, Theme.glow.opacity(0)], center: UnitPoint(x: 0.5, y: 86 / 210),
                       startRadiusFraction: 0, endRadiusFraction: 0.5)
      .frame(width: 340, height: 210)
      .opacity(lit ? 1 : 0)
      .animation(.easeInOut(duration: 0.6), value: lit)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

private struct MainPage: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Header(model: model)
        .padding(.bottom, 12)
      switch model.phase {
      case .idle:
        if !model.fixRows.isEmpty {
          SetupCard(model: model)
            .padding(.bottom, 12)
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        }
        Hero(model: model)
        PlacePicker(selection: $model.place)
          .padding(.top, 12)
        PlaceHint(place: model.place)
          .padding(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
        NoteField(model: model)
          .padding(.top, 10)
        Recent(model: model)
      case .arming:
        MiniCountdown(model: model)
      case .armed, .triggered:
        Text(L("Rest a finger on Touch ID, or unlock the Mac, to stop"))
          .font(Theme.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// The tile, the name, one status chip and the ⋯ menu (audit A3).
private struct Header: View {
  @ObservedObject var model: PanelModel
  var title = "Back in 5"
  var showsStatus = true

  var body: some View {
    HStack(spacing: 9) {
      PanelTile(model: model)
      Text(verbatim: title)
        .font(.system(size: 13, weight: .semibold))
      if showsStatus {
        StatusChip(tone: tone, text: chip)
          .help(statusTip)
      }
      Spacer(minLength: 6)
      if showsStatus && model.phase == .idle {
        MoreButton(model: model)
      }
    }
    .frame(height: 28)
  }

  /// What is on, for whoever points at the chip.
  private var statusTip: String {
    guard model.phase == .idle else { return "" }
    return model.statusRows.map { row in row.title + " · " + (row.on ? L("On") : L("Off")) }.joined(separator: "\n")
  }

  private var tone: StatusChip.Tone {
    switch model.phase {
    case .arming, .armed: return .warn
    case .triggered: return .alarm
    case .idle: return model.checks.isEmpty ? .busy : model.locked ? .warn : .ok
    }
  }

  private var chip: String {
    switch model.phase {
    case .arming: return L("Starting…")
    case .armed: return L("Guarding")
    case .triggered: return L("Alarm raised")
    case .idle:
      if model.checks.isEmpty { return L("Checking…") }
      if model.locked { return model.toFix == 1 ? L("1 thing to fix") : L("%ld things to fix", model.toFix) }
      return L("Ready")
    }
  }
}

/// The panel's tile looks like the menu bar (audit A4): an outline while idle, amber rising while
/// counting down, amber with the watch light while guarding, red on an alarm.
private struct PanelTile: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    if model.phase == .arming {
      TimelineView(.animation) { tl in
        Tile(look: .arming(tl.date.timeIntervalSince(model.countdownFrom) / GuardApp.countdownSeconds))
      }
    } else {
      Tile(look: model.phase == .armed ? .guarding : model.phase == .triggered ? .alarm : .outline)
    }
  }
}

private struct StatusChip: View {
  enum Tone: Equatable { case ok, warn, alarm, busy }
  let tone: Tone
  let text: String
  @State private var pop: CGFloat = 1

  var body: some View {
    HStack(spacing: 6) {
      dot
        .frame(width: 8, height: 8)
        .scaleEffect(pop)
      Text(text)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .contentTransition(.opacity)
    }
    .padding(.leading, 7)
    .padding(.trailing, 8)
    .frame(height: 20)
    .background(Capsule().fill(Theme.fill))
    .animation(.easeInOut(duration: 0.3), value: text)
    .animation(.easeInOut(duration: 0.3), value: tone)
    .onChange(of: tone) { old, new in
      guard old != new, new != .busy else { return }
      replay(.spring(response: 0.42, dampingFraction: 0.4)) { pop = $0 ? 1 : 0.2 }
    }
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var dot: some View {
    switch tone {
    case .busy: Spinner()
    case .ok: Dot(color: Theme.green)
    case .warn: Dot(color: Theme.amberDeep)
    case .alarm: Dot(color: Theme.red, halo: false)
    }
  }
}

private struct Dot: View {
  let color: Color
  var halo = true

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 6, height: 6)
      .background {
        if halo { Circle().fill(color.opacity(0.22)).frame(width: 11, height: 11) }
      }
  }
}

private struct Spinner: View {
  @State private var turned = false

  var body: some View {
    Circle()
      .trim(from: 0, to: 0.72)
      .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
      .frame(width: 8, height: 8)
      .rotationEffect(.degrees(turned ? 360 : 0))
      .onAppear {
        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { turned = true }
      }
  }
}

/// Jumps to the start at once, then animates to the end: a one-shot pop or sweep. `set(false)` is
/// the start, `set(true)` the end.
func replay(_ animation: Animation, _ set: @escaping (Bool) -> Void) {
  var t = Transaction()
  t.disablesAnimations = true
  withTransaction(t) { set(false) }
  DispatchQueue.main.async {
    withAnimation(animation) { set(true) }
  }
}

/// ⋯: Settings, how it works, the recordings, quit. A native menu, with its shortcuts and an icon on
/// every item. What is on lives in the Ready chip's tooltip and Settings' Checks: read-only rows in a
/// menu can only be drawn dimmed, and they read as broken buttons.
private struct MoreButton: View {
  @ObservedObject var model: PanelModel
  @State private var hover = false

  var body: some View {
    Button(action: show) {
      Image(systemName: "ellipsis")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(hover ? Color.primary : Color.secondary)
        .frame(width: 26, height: 26)
        .background(Circle().fill(hover ? Theme.fill : Color.clear))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
    .help(L("More"))
    .accessibilityLabel(L("More"))
  }

  private func show() {
    let menu = NSMenu()
    func item(_ symbol: String, _ title: String, _ key: String = "", _ run: @escaping () -> Void) {
      let action = MenuAction(run)
      let i = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: key)
      i.target = action
      i.representedObject = action  // the item keeps its action alive
      i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
      menu.addItem(i)
    }
    item("gearshape", L("Settings…"), ",") { model.onSettings(.general) }
    item("questionmark.circle", L("How it works")) { model.showIntro() }
    item("folder", L("Open Recordings Folder")) { model.reveal(nil) }
    menu.addItem(.separator())
    item("power", L("Quit Back in 5"), "q") { NSApp.terminate(nil) }
    menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
  }
}

final class MenuAction: NSObject {
  let run: () -> Void
  init(_ run: @escaping () -> Void) { self.run = run }
  @objc func fire() { run() }
}

/// "Before guarding": only what is missing, each with the button that fixes it.
private struct SetupCard: View {
  @ObservedObject var model: PanelModel
  @State private var flash = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(L("Before guarding"))
          .font(.system(size: 12, weight: .semibold))
        Spacer(minLength: 8)
        Text(verbatim: "\(model.setupDone) / \(model.setupTotal)")
          .font(.system(size: 12, weight: .medium))
          .monospacedDigit()
          .foregroundStyle(.tertiary)
          .contentTransition(.numericText())
          .animation(.default, value: model.setupDone)
      }
      .padding(EdgeInsets(top: 10, leading: 12, bottom: 2, trailing: 12))
      ForEach(Array(model.fixRows.enumerated()), id: \.element.id) { i, check in
        FixRow(check: check, divider: i > 0, busy: model.installing && check.id == .sleep) { model.fix(check) }
          .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
      }
    }
    .background(LinearGradient(colors: [Theme.amber.opacity(0.11), Theme.amber.opacity(0.05)], startPoint: .top, endPoint: .bottom))
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.amber.opacity(flash ? 0.95 : 0.38), lineWidth: flash ? 1.5 : 0.5))
    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.amber.opacity(flash ? 0.18 : 0), lineWidth: 4).padding(-4))
    .onChange(of: model.lockedNudge) { _, _ in
      withAnimation(.easeOut(duration: 0.2)) { flash = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
        withAnimation(.easeInOut(duration: 0.45)) { flash = false }
      }
    }
  }
}

private struct FixRow: View {
  let check: Check
  let divider: Bool
  let busy: Bool
  let fix: () -> Void

  var body: some View {
    HStack(spacing: 9) {
      ZStack {
        Image(systemName: "exclamationmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(Theme.ink, Theme.amberDeep)
          .scaleEffect(check.ok ? 0.3 : 1)
          .opacity(check.ok ? 0 : 1)
        Image(systemName: "checkmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(Color.white, Theme.green)
          .scaleEffect(check.ok ? 1 : 0.3)
          .opacity(check.ok ? 1 : 0)
      }
      .font(.system(size: 16))
      .frame(width: 18, height: 18)
      .animation(.spring(response: 0.35, dampingFraction: 0.55), value: check.ok)
      VStack(alignment: .leading, spacing: 1) {
        Text(check.title)
          .font(.system(size: 13, weight: .medium))
        Text(check.detail)
          .font(Theme.label)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .id(check.detail)
          .transition(.opacity)
      }
      .animation(.easeInOut(duration: 0.25), value: check.detail)
      Spacer(minLength: 6)
      Button(action: fix) {
        HStack(spacing: 5) {
          if busy { ProgressView().controlSize(.mini) }
          Text(label)
        }
      }
      .controlSize(.small)
      .disabled(busy || check.ok)
      .opacity(check.ok ? 0 : 1)
      .animation(.easeOut(duration: 0.2), value: check.ok)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .overlay(alignment: .top) {
      if divider { Rectangle().fill(Theme.separator).frame(height: 0.5).padding(.horizontal, 12) }
    }
  }

  private var label: String {
    switch check.id {
    case .accessibility: L("Open Settings")
    case .camera: check.askable ? L("Allow") : L("Open Settings")
    case .sleep: busy ? L("Installing…") : L("Install")
    case .push: L("Set up")
    default: L("Check again")
    }
  }
}

/// The start button: amber and ready, striped for a silent run, or a quiet well with a lock while
/// something is missing. ↩ presses it from anywhere in the panel (audit B5, B6).
private struct Hero: View {
  @ObservedObject var model: PanelModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var focused: Bool
  @State private var hover = false
  @State private var shine = false
  @State private var badgeScale: CGFloat = 1

  var body: some View {
    let locked = model.locked
    let silent = (model.testMode || model.optionHeld) && !locked
    let lift = hover && !locked
    Button(action: model.arm) {
      HStack(spacing: 12) {
        badge(locked, lift: lift)
        words(locked, silent)
        Keycap { Text(verbatim: "↩").font(.system(size: 12, weight: .semibold)) }
          .opacity(locked ? 0 : 1)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity)
      .frame(height: 64)
      .foregroundStyle(locked ? Color.secondary : Theme.ink)
      .background(HeroGround(locked: locked, silent: silent, hover: hover))
      .overlay(sweep)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .brightness(lift ? 0.03 : 0)
      .saturation(lift ? 1.06 : 1)
    }
    .buttonStyle(HeroPress())
    .keyboardShortcut(.defaultAction)
    .focusEffectDisabled()
    .focused($focused)
    .shadow(color: Theme.amberShadow.opacity(locked ? 0 : lift ? 0.38 : 0.3), radius: lift ? 12 : 8, y: lift ? 9 : 6)
    .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Theme.amber.opacity(0.8), lineWidth: 2.5).padding(-4).opacity(focused ? 1 : 0))
    .modifier(Shake(model.lockedNudge))
    .animation(.timingCurve(0.36, 0.07, 0.19, 0.97, duration: 0.42), value: model.lockedNudge)
    .animation(.easeInOut(duration: 0.35), value: locked)
    .animation(.easeInOut(duration: 0.3), value: silent)
    .animation(.easeOut(duration: 0.2), value: hover)
    .onHover { hover = $0 }
    .help(locked || model.testMode ? "" : L("Hold ⌥ for a silent run"))
    .onChange(of: model.bloom) { _, _ in bloom() }
  }

  private func badge(_ locked: Bool, lift: Bool) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(locked ? Theme.fill : Theme.ink.opacity(0.1))
      if locked {
        Image(systemName: "lock")
          .font(.system(size: 17, weight: .medium))
          .transition(.scale(scale: 0.6).combined(with: .opacity))
      } else {
        ShieldGlyph(look: .ink)
          .frame(width: 22, height: 22)
          .transition(.scale(scale: 0.6).combined(with: .opacity))
      }
    }
    .frame(width: 40, height: 40)
    .scaleEffect(badgeScale * (lift ? 1.04 : 1))
    .offset(y: lift ? -1 : 0)
    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: lift)
  }

  private func words(_ locked: Bool, _ silent: Bool) -> some View {
    let label = silent ? L("Try a silent run") : L("Start guarding")
    let sub = locked ? (model.toFix == 1 ? L("Fix the 1 above first") : L("Fix the %ld above first", model.toFix))
      : !silent ? L("Starts in 5 s · leave it lying still")
      : model.testMode ? L("This run stays silent, then test mode turns off") : L("This run stays silent")
    return ZStack(alignment: .leading) {
      VStack(alignment: .leading, spacing: 1) {
        Text(label)
          .font(.system(size: 15, weight: .semibold))
          .lineLimit(1)
        Text(sub)
          .font(.system(size: 11, weight: .medium))
          .opacity(0.74)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .id(label + sub)
      .transition(.words())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(Theme.out(0.3), value: label + sub)
  }

  /// Light crossing the button once the last missing piece is fixed.
  private var sweep: some View {
    GeometryReader { g in
      LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .white.opacity(0.55), location: 0.48),
                             .init(color: .white.opacity(0.1), location: 0.56), .init(color: .clear, location: 0.7)],
                     startPoint: UnitPoint(x: 0, y: 0.4), endPoint: UnitPoint(x: 1, y: 0.6))
        .frame(width: g.size.width, height: g.size.height)
        .offset(x: shine ? g.size.width * 1.1 : -g.size.width * 1.1)
    }
    .allowsHitTesting(false)
  }

  private func bloom() {
    guard !reduceMotion else { return }
    replay(Theme.out(0.9).delay(0.1)) { shine = $0 }
    replay(.spring(response: 0.4, dampingFraction: 0.4)) { badgeScale = $0 ? 1 : 0.8 }
  }
}

private struct HeroGround: View {
  let locked: Bool
  let silent: Bool
  let hover: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.fill)
      RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5)
      ZStack {
        LinearGradient(colors: [Theme.amberHi, Theme.amberDeep], startPoint: .top, endPoint: .bottom)
        if silent {
          // The test-mode switch's stripes; they march while the pointer is on the button.
          TimelineView(.animation(minimumInterval: nil, paused: !hover)) { tl in
            Stripes(band: 7, offset: hover ? -CGFloat(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 * 40) : 0)
          }
          .background(Theme.amberDeep)
          .transition(.opacity)
        }
        VStack(spacing: 0) {
          Color.white.opacity(0.6).frame(height: 1)
          Spacer(minLength: 0)
          Color(red: 140 / 255, green: 70 / 255, blue: 0).opacity(0.22).frame(height: 1)
        }
      }
      .opacity(locked ? 0 : 1)
    }
  }
}

private struct HeroPress: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.975 : 1)
      .animation(.spring(response: 0.26, dampingFraction: 0.6), value: configuration.isPressed)
  }
}

struct Pressable: ButtonStyle {
  var scale: CGFloat = 0.97

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? scale : 1)
      .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
  }
}

/// Library, café, on the go: three tiles, the chosen one lit amber like the start button it sets up
/// (audit B1). ← → move it too.
private struct PlacePicker: View {
  @Binding var selection: Place

  var body: some View {
    HStack(spacing: 6) {
      ForEach(Place.allCases, id: \.self) { place in
        PlaceTile(place: place, on: place == selection) { selection = place }
      }
    }
  }
}

private struct PlaceTile: View {
  let place: Place
  let on: Bool
  let pick: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hover = false
  @State private var pop: CGFloat = 1
  @State private var bounces = 0

  var body: some View {
    Button(action: pick) {
      VStack(spacing: 6) {
        orb
        Text(place.title)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(on || hover ? Color.primary : Color.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.85)
      }
      .padding(EdgeInsets(top: 10, leading: 4, bottom: 9, trailing: 4))
      .frame(maxWidth: .infinity)
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Theme.placeOn : hover ? Theme.fill2 : Theme.fill))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.amber.opacity(0.55) : Theme.separator, lineWidth: 0.5))
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(Pressable(scale: 0.96))
    .onHover { hover = $0 }
    .animation(.easeOut(duration: 0.25), value: on)
    .animation(.easeOut(duration: 0.25), value: hover)
    .onChange(of: on) { _, now in
      guard now, !reduceMotion else { return }
      bounces += 1
      replay(.spring(duration: 0.5, bounce: 0.35)) { pop = $0 ? 1 : 0.78 }
    }
    .accessibilityAddTraits(on ? .isSelected : [])
  }

  /// A quiet well, or the start button's amber with its highlight and shadow; the glyph dips as it
  /// lights.
  private var orb: some View {
    ZStack {
      Circle().fill(Theme.fill2)
      Circle()
        .fill(LinearGradient(colors: [Theme.amberHi, Theme.amberDeep], startPoint: .top, endPoint: .bottom))
        .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 0.5))
        .shadow(color: Theme.amberShadow.opacity(0.35), radius: 4, y: 2)
        .opacity(on ? 1 : 0)
      Image(systemName: place.symbol)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(on ? Theme.ink : Color.secondary)
        .symbolEffect(.bounce.down, value: bounces)
    }
    .frame(width: 32, height: 32)
    .scaleEffect(pop)
  }
}

/// What counts at this place. All three lines are laid out, so the panel keeps its height.
private struct PlaceHint: View {
  let place: Place

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(Place.allCases, id: \.self) { p in
        let on = p == place
        Text(p.hint)
          .font(Theme.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .opacity(on ? 1 : 0)
          .offset(y: on ? 0 : 5)
          .blur(radius: on ? 0 : 2)
          .accessibilityHidden(!on)
      }
    }
    .animation(Theme.out(0.35), value: place)
  }
}

/// The note on the notice: counts from 16 characters, shakes at the limit, clears with one click,
/// and ↩ starts guarding (audit B2).
private struct NoteField: View {
  @ObservedObject var model: PanelModel
  @FocusState private var focused: Bool

  var body: some View {
    let n = model.note.count
    HStack(spacing: 8) {
      Image(systemName: "text.bubble")
        .font(.system(size: 13))
        .foregroundStyle(.tertiary)
      TextField("", text: $model.note, prompt: Text(L("Note on the screen, e.g. Back in 10 min")))
        .textFieldStyle(.plain)
        .font(Theme.body)
        .focused($focused)
        .onSubmit(model.arm)
      Text(verbatim: "\(n)/\(Prefs.noteLimit)")
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(n >= Prefs.noteLimit ? Theme.warn : Color.secondary)
        .opacity(n >= 16 ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: n >= 16)
      Button {
        model.note = ""
        focused = true
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 13))
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
      .opacity(n > 0 ? 1 : 0)
      .scaleEffect(n > 0 ? 1 : 0.6)
      .allowsHitTesting(n > 0)
      .animation(.spring(response: 0.25, dampingFraction: 0.6), value: n > 0)
      .help(L("Clear"))
      .accessibilityLabel(L("Clear"))
    }
    .padding(.leading, 10)
    .padding(.trailing, 8)
    .frame(height: 34)
    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(focused ? Theme.input : Theme.fill))
    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.amberDeep.opacity(0.9), lineWidth: 1).opacity(focused ? 1 : 0))
    .overlay(RoundedRectangle(cornerRadius: 12.5, style: .continuous).strokeBorder(Theme.amber.opacity(0.32), lineWidth: 3.5).padding(-3.5).opacity(focused ? 1 : 0))
    .animation(.easeOut(duration: 0.18), value: focused)
    .modifier(Shake(model.noteBump, amount: 5))
    .animation(.linear(duration: 0.32), value: model.noteBump)
  }
}

/// The last three sessions, two while the setup card needs the room: what happened, when, and the
/// recording one click away (audit A6, A7).
private struct Recent: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    let list = Array(model.history.prefix(model.fixRows.isEmpty ? 3 : 2))
    if !list.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        Text(L("Recent"))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 4)
          .padding(.top, 20)
          .padding(.bottom, 4)
        ForEach(list, id: \.armed) { s in
          RecentRow(session: s, isNew: model.isNew(s)) { model.reveal(s.clip) }
            .transition(.opacity.combined(with: .offset(y: -6)))
        }
      }
    }
  }
}

private struct RecentRow: View {
  let session: Session
  let isNew: Bool
  let reveal: () -> Void
  @State private var hover = false

  var body: some View {
    if session.clip != nil {
      Button(action: reveal) { row }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L("Show in Finder"))
    } else {
      row
    }
  }

  /// "New" sits on the first line, so the second has the row's whole width.
  private var row: some View {
    HStack(spacing: 8) {
      tile
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(session.title)
            .font(Theme.body)
            .foregroundStyle(session.alarmed && !session.test ? Theme.warn : Color.primary)
            .lineLimit(1)
          Spacer(minLength: 0)
          if isNew {
            Text(L("New"))
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 6)
              .frame(height: 16)
              .background(Capsule().fill(Theme.red))
          }
        }
        Text(session.detail)
          .font(Theme.label)
          .monospacedDigit()
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Theme.fill : Color.clear))
    .contentShape(Rectangle())
    .animation(.easeOut(duration: 0.15), value: hover)
  }

  /// Green for a quiet session, red for an alarm, the silent run's stripes for a test: the same
  /// colors as the phone's list. Pointing at a row with a recording turns the mark into the arrow
  /// that shows it in Finder.
  private var tile: some View {
    let s = session
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    let mark = s.alarmed ? "exclamationmark" : s.quiet ? "checkmark" : "minus"
    return Image(systemName: hover ? "arrow.up.forward" : mark)
      .font(.system(size: 11, weight: .bold))
      .contentTransition(.symbolEffect(.replace))
      .foregroundStyle(s.test ? Theme.ink : s.alarmed ? Theme.red : s.quiet ? Theme.green : Color.secondary)
      .frame(width: 26, height: 26)
      .background {
        if s.test {
          Stripes(band: 4).background(Theme.amberDeep).clipShape(shape)
        } else {
          shape.fill(s.alarmed ? Theme.red.opacity(0.16) : s.quiet ? Theme.green.opacity(0.15) : Theme.fill)
        }
      }
  }
}

/// The countdown in the panel, when the frosted screen is off (audit A8).
private struct MiniCountdown: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 4)
        TimelineView(.animation) { tl in
          Circle()
            .trim(from: 0, to: min(1, tl.date.timeIntervalSince(model.countdownFrom) / GuardApp.countdownSeconds))
            .stroke(Theme.amberDeep, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
        }
        Text(verbatim: "\(model.remaining)")
          .font(.system(size: 22, weight: .light, design: .rounded))
          .monospacedDigit()
          .contentTransition(.numericText(countsDown: true))
          .animation(.default, value: model.remaining)
      }
      .frame(width: 48, height: 48)
      .padding(4)
      VStack(alignment: .leading, spacing: 2) {
        Text(L("Guarding starts in %ld s", model.remaining))
          .font(Theme.title)
        Text(L("esc cancels too"))
          .font(Theme.caption)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      Button(L("Cancel"), action: model.onCancel)
        .controlSize(.small)
    }
  }
}

/// Three cards on first launch: what it does, what it records, how to stop it. Each has a small
/// film of what it says; the cards slide the way you go, and the dots can be clicked (audit B7).
/// The last offers a silent first run, so the first alarm anyone hears is never a surprise.
private struct IntroPage: View {
  @ObservedObject var model: PanelModel
  private var step: Int { model.introStep }

  private var cards: [(title: String, text: String)] {
    [
      (L("Start it before you step away"),
       L("Every screen frosts over and asks people not to touch. Lifting, tilting or closing the Mac, a key or a click sounds the alarm.")),
      (L("Walking by isn't recorded"),
       L("The camera keeps only the last 10 seconds, in memory. They are saved, with the faces behind the person blurred, only when someone touches the Mac.")),
      (L("Back? Rest a finger on Touch ID"),
       L("Touch ID or unlocking the Mac stops it. Try it once in test mode first: nothing makes a sound.")),
    ]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Header(model: model, title: L("Welcome to Back in 5"), showsStatus: false)
        .padding(.bottom, 12)
      ZStack(alignment: .topLeading) {
        card(step)
          .id(step)
          .transition(.asymmetric(insertion: .offset(x: model.introForward ? 26 : -26).combined(with: .opacity),
                                  removal: .offset(x: model.introForward ? -26 : 26).combined(with: .opacity)))
      }
      HStack(spacing: 8) {
        dots
        Spacer(minLength: 8)
        Button(step == 0 ? L("Skip") : step == 2 ? L("Later") : L("Back")) {
          if step == 1 { model.goIntro(0) } else { model.finishIntro(tryIt: false) }
        }
        .buttonStyle(QuietButton())
        Button(step < 2 ? L("Next") : L("Try a silent run")) {
          if step < 2 { model.goIntro(step + 1) } else { model.finishIntro(tryIt: true) }
        }
        .buttonStyle(AmberButton())
        .keyboardShortcut(.defaultAction)
      }
      .padding(.top, 14)
      if step == 2 {
        Text(L("Back in 5 asks for Accessibility and the camera on the way."))
          .font(Theme.label)
          .foregroundStyle(.tertiary)
          .padding(.top, 10)
          .padding(.horizontal, 2)
          .transition(.opacity)
      }
    }
  }

  private func card(_ i: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      IntroFilm(step: i)
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Theme.tile)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
      Text(cards[i].title)
        .font(Theme.title)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 14)
        .padding(.bottom, 5)
        .padding(.horizontal, 2)
      Text(cards[i].text)
        .font(Theme.caption)
        .foregroundStyle(.secondary)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .padding(.horizontal, 2)
    }
  }

  private var dots: some View {
    HStack(spacing: 6) {
      ForEach(0..<3, id: \.self) { i in
        Button {
          model.goIntro(i)
        } label: {
          Capsule()
            .fill(i == step ? Theme.amberDeep : Color.secondary.opacity(0.45))
            .frame(width: i == step ? 18 : 6, height: 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(i + 1) / 3"))
      }
    }
    .padding(.leading, 2)
    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: step)
  }
}

/// A small amber push button: the intro's next step.
struct AmberButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(Theme.ink)
      .padding(.horizontal, 12)
      .frame(height: 24)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(LinearGradient(colors: [Theme.amberHi, Theme.amberDeep], startPoint: .top, endPoint: .bottom)))
      .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
        .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center), lineWidth: 0.5))
      .shadow(color: Color(red: 190 / 255, green: 110 / 255, blue: 0).opacity(0.3), radius: 1.5, y: 1)
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .brightness(configuration.isPressed ? -0.03 : 0)
      .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
  }
}

/// Words only, for the way out: Skip, Back, Later.
private struct QuietButton: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    QuietLabel(configuration: configuration)
  }

  private struct QuietLabel: View {
    let configuration: ButtonStyleConfiguration
    @State private var hover = false

    var body: some View {
      configuration.label
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(hover ? Color.primary : Color.secondary)
        .padding(.horizontal, 6)
        .frame(height: 24)
        .contentShape(Rectangle())
        .opacity(configuration.isPressed ? 0.6 : 1)
        .onHover { hover = $0 }
    }
  }
}

/// The three little films: the screen frosting over, the last 10 seconds kept in memory, a finger
/// on Touch ID. Each loops from the moment its card appears; with Reduce Motion, one still frame.
private struct IntroFilm: View {
  let step: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var start = Date()

  var body: some View {
    TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { tl in
      let t = reduceMotion ? [2.6, 3.4, 1.6][step] : tl.date.timeIntervalSince(start)
      switch step {
      case 0: FrostFilm(t: t)
      case 1: MemoryFilm(t: t)
      default: TouchFilm(t: t)
      }
    }
  }
}

/// Keyframes over one loop (0…1), eased between: held before the first and after the last.
private func keyframes(_ q: Double, _ frames: [(Double, Double)], _ ease: Ease = .out) -> Double {
  guard let first = frames.first, let last = frames.last else { return 0 }
  if q <= first.0 { return first.1 }
  if q >= last.0 { return last.1 }
  for (a, b) in zip(frames, frames.dropFirst()) where q <= b.0 {
    return a.1 + (b.1 - a.1) * ease((q - a.0) / max(b.0 - a.0, 0.0001))
  }
  return last.1
}

/// CSS's springy cubic-bezier(.3, 1.35, .5, 1): overshoots a little and settles.
private let springy = Ease(0.3, 1.35, 0.5, 1)

private struct FrostFilm: View {
  let t: Double

  var body: some View {
    let q = (t / 4.2).truncatingRemainder(dividingBy: 1)
    let fog = keyframes(q, [(0.08, 0), (0.45, 1)])
    let fade = keyframes(q, [(0.88, 1), (1, 0)], Ease(0.4, 0, 0.6, 1))
    let notice = keyframes(q, [(0.4, 0), (0.52, 1)], springy)
    let reach = 117 * fog
    ZStack {
      ZStack(alignment: .topLeading) {
        LinearGradient(colors: [Color(red: 0x3A / 255, green: 0x4A / 255, blue: 0x8E / 255), Color(red: 0x12 / 255, green: 0x1A / 255, blue: 0x3A / 255)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        lines
        lines
          .blur(radius: 2.5)
          .background(Color(red: 160 / 255, green: 175 / 255, blue: 210 / 255).opacity(0.28))
          .mask(Circle().frame(width: reach * 2, height: reach * 2).position(x: 88, y: 48.6))
          .opacity(fade)
        HStack(spacing: 6) {
          ShieldGlyph(look: .guarding).frame(width: 16, height: 16)
          Capsule().fill(.white.opacity(0.8)).frame(height: 4)
        }
        .padding(.horizontal, 8)
        .frame(width: 92, height: 30)
        .background(Capsule().fill(.white.opacity(0.18)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
        .scaleEffect(0.4 + 0.6 * notice)
        .opacity(min(notice, fade))
        .position(x: 88, y: 54)
      }
      .frame(width: 176, height: 108)
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .padding(3)
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 8 / 255, green: 9 / 255, blue: 12 / 255)))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1).padding(-1))
      .offset(y: -6)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var lines: some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach([112.0, 94, 124, 80], id: \.self) { w in
        Capsule().fill(.white.opacity(0.22)).frame(width: w, height: 5)
      }
    }
    .padding(.leading, 12)
    .padding(.top, 14)
    .frame(width: 176, height: 108, alignment: .topLeading)
  }
}

private struct MemoryFilm: View {
  let t: Double

  var body: some View {
    let roll = CGFloat(t.truncatingRemainder(dividingBy: 1)) * 38
    let q = (t / 4.2).truncatingRemainder(dividingBy: 1)
    let kept = keyframes(q, [(0.5, 0), (0.58, 1), (0.92, 1), (1, 0)], Ease(0.25, 0.1, 0.25, 1))
    GeometryReader { g in
      let w = g.size.width - 44
      ZStack(alignment: .topLeading) {
        Text(L("in memory · 10 s"))
          .font(.system(size: 10.5, weight: .semibold))
          .tracking(0.4)
          .foregroundStyle(.white.opacity(0.6))
          .position(x: 22, y: 18)
          .fixedSize()
          .frame(width: w, alignment: .leading)
          .offset(x: 22, y: 12)
        HStack(spacing: 4) {
          ForEach(0..<16, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 5, style: .continuous)
              .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
              .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
              .frame(width: 34, height: 44)
          }
        }
        .offset(x: -roll)
        .frame(width: w, height: 44, alignment: .leading)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18)], startPoint: .leading, endPoint: .trailing))
        .offset(x: 22, y: 44)
        HStack {
          Text(verbatim: "−10 s")
          Spacer()
          Text(verbatim: "−5 s")
          Spacer()
          Text(L("now"))
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.55))
        .frame(width: w)
        .offset(x: 22, y: 96)
        VStack(spacing: 6) {
          Text(L("saved"))
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color(red: 1, green: 0x8A / 255, blue: 0x90 / 255))
            .fixedSize()
          Rectangle()
            .fill(Theme.red)
            .frame(width: 2, height: 64)
            .shadow(color: Theme.red.opacity(0.7), radius: 5)
        }
        .opacity(kept)
        .position(x: 22 + w - 1, y: 36 + 32 - 8)
      }
    }
  }
}

private struct TouchFilm: View {
  let t: Double

  var body: some View {
    let q = (t / 3.2).truncatingRemainder(dividingBy: 1)
    let ripple = q < 0.4 ? 0 : keyframes(q, [(0.4, 0), (0.75, 1)], Ease(0, 0, 0.58, 1))
    let away = keyframes(q, [(0, 1), (0.34, 0), (0.6, 0), (0.8, 1)], Ease(0.22, 0.9, 0.3, 1))
    let finger = keyframes(q, [(0, 0), (0.18, 0.92), (0.6, 0.92), (0.8, 0)])
    let shield = keyframes(q, [(0.42, 0), (0.52, 1), (0.86, 1), (1, 0)], springy)
    GeometryReader { g in
      let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
      ZStack {
        RoundedRectangle(cornerRadius: 16 + 13 * ripple, style: .continuous)
          .stroke(Theme.green.opacity(0.7 * (1 - ripple)), lineWidth: 26 * ripple)
          .frame(width: 64 + 26 * ripple, height: 64 + 26 * ripple)
          .opacity(ripple > 0 ? 1 : 0)
          .position(c)
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .fill(LinearGradient(colors: [Color(red: 0x2B / 255, green: 0x2D / 255, blue: 0x36 / 255), Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x1C / 255)],
                               startPoint: .top, endPoint: .bottom))
          .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
          .overlay(Image(systemName: "touchid").font(.system(size: 30)).foregroundStyle(.white.opacity(0.5)))
          .frame(width: 64, height: 64)
          .shadow(color: .black.opacity(0.4), radius: 9, y: 6)
          .position(c)
        UnevenRoundedRectangle(topLeadingRadius: 15, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 15, style: .continuous)
          .fill(LinearGradient(colors: [Color(red: 0xF2 / 255, green: 0xC6 / 255, blue: 0xA6 / 255), Color(red: 0xD9 / 255, green: 0xA0 / 255, blue: 0x7C / 255)],
                               startPoint: .top, endPoint: .bottom))
          .frame(width: 30, height: 40)
          .rotationEffect(.degrees(18 * away))
          .offset(x: 40 * away, y: 60 * away)
          .opacity(finger)
          .position(x: c.x, y: c.y + 10)
        ShieldGlyph(look: .clear)
          .frame(width: 30, height: 30)
          .scaleEffect(0.3 + 0.7 * shield)
          .opacity(min(1, shield))
          .position(x: g.size.width - 26 - 15, y: 26 + 15)
      }
    }
  }
}

/// Design A's switch: the label on the left, the switch at the trailing edge, amber when on. Test
/// mode's is striped, as everything silent is. The knob stretches while pressed.
struct AmberSwitch: ToggleStyle {
  var striped = false

  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 12) {
      configuration.label
      Spacer(minLength: 0)
      Button { configuration.isOn.toggle() } label: { EmptyView() }
        .buttonStyle(SwitchBody(on: configuration.isOn, striped: striped))
    }
    .accessibilityElement(children: .combine)
    .accessibilityValue(configuration.isOn ? L("On") : L("Off"))
  }
}

private struct SwitchBody: ButtonStyle {
  let on: Bool
  let striped: Bool

  func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed
    return ZStack(alignment: on ? .trailing : .leading) {
      Capsule().fill(on ? Theme.amberDeep : Theme.fill2)
      if on && striped {
        Stripes(band: 4.2).clipShape(Capsule())
      }
      Capsule().strokeBorder(Theme.separator, lineWidth: 0.5)
      Capsule()
        .fill(Color.white)
        .shadow(color: .black.opacity(0.3), radius: 1.25, y: 1)
        .frame(width: pressed ? 22 : 18, height: 18)
        .padding(2)
    }
    .frame(width: 38, height: 22)
    .contentShape(Capsule())
    .animation(.spring(response: 0.34, dampingFraction: 0.62), value: on)
    .animation(Theme.out(0.2), value: pressed)
  }
}

struct Step: View {
  let n: Int
  let text: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Text(verbatim: "\(n)")
        .font(.system(size: 10.5, weight: .bold))
        .foregroundStyle(Theme.ink)
        .frame(width: 16, height: 16)
        .background(Circle().fill(Theme.amber))
      Text(text)
        .font(Theme.caption)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

struct QRView: View {
  let text: String

  var body: some View {
    Group {
      if let image = QR.image(text) {
        Image(nsImage: image).interpolation(.none).resizable()
      } else {
        Color.secondary.opacity(0.2)
      }
    }
    .frame(width: 104, height: 104)
    .padding(6)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
  }
}

enum QR {
  static func image(_ text: String) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let code = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
          let cg = CIContext().createCGImage(code, from: code.extent) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
  }
}
