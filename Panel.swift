import AppKit
import AVFoundation
import Carbon
import CoreImage.CIFilterBuiltins
import LocalAuthentication
import SwiftUI

/// The menu-bar panel: arm, where the Mac is, a note for the screen, siren volume, test mode, the
/// frosted screen, the phone, recordings and the last few sessions. When something is missing it
/// says what, and fixes what it can (audit M4: no more modal alerts).
final class Panel {
  let model = PanelModel()
  private let popover = NSPopover()

  init() {
    popover.behavior = .transient
    popover.animates = true
    let host = NSHostingController(rootView: PanelView(model: model))
    host.sizingOptions = .preferredContentSize
    popover.contentViewController = host
    model.onClose = { [weak self] in self?.close() }
  }

  var isShown: Bool { popover.isShown }

  func toggle(from button: NSStatusBarButton) {
    if popover.isShown { close(); return }
    model.page = .main
    model.refresh()
    NSApp.activate(ignoringOtherApps: true)  // an accessory app's text field needs this for typing
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }

  func close() {
    if popover.isShown { popover.performClose(nil) }
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

/// What arming needs, checked without side effects unless `prompt` is set (then macOS asks for
/// Accessibility and the camera). The sudo check runs off the main thread (audit L5).
enum Preflight {
  static func run(prompt: Bool, _ done: @escaping ([Check]) -> Void) {
    let trusted = prompt ? AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
                         : AXIsProcessTrusted()
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    if prompt && status == .notDetermined { AVCaptureDevice.requestAccess(for: .video) { _ in } }
    let camera = Recorder.camera != nil
    let speakers = Alarm.builtInSpeakers() != nil
    var error: NSError?
    let touchID = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    let secure = IsSecureEventInputEnabled()
    let lock = GuardApp.lockScreen != nil
    DispatchQueue.global(qos: .userInitiated).async {
      let sleep = sleepRuleInstalled()
      DispatchQueue.main.async {
        done([
          Check(id: .accessibility, title: L("Accessibility"),
                detail: trusted ? L("Notices the keyboard and trackpad") : L("Needed to notice the keyboard and trackpad"), ok: trusted),
          Check(id: .camera, title: L("Camera"),
                detail: !camera ? L("No built-in camera found")
                  : status == .authorized ? L("Films only around an alarm")
                  : status == .notDetermined ? L("Allow it so an alarm can be recorded") : L("Turned off for GuardMode in System Settings"),
                ok: camera && status == .authorized, askable: status == .notDetermined),
          Check(id: .sleep, title: L("Stay awake with the lid shut"),
                detail: sleep ? L("Keeps guarding with the lid closed") : L("Needs an admin rule, installed once from Terminal"), ok: sleep),
          Check(id: .speakers, title: L("Speakers"),
                detail: speakers ? L("The siren plays on the built-in speakers") : L("No built-in speakers found"), ok: speakers),
          Check(id: .touchID, title: L("Touch ID"),
                detail: touchID ? L("Rest a finger to stop guarding") : L("Unlock the Mac to stop guarding instead"), ok: touchID, optional: true),
          Check(id: .push, title: L("Phone alerts"),
                detail: Push.enabled ? L("On") : L("Off: alarms stay on this Mac"), ok: Push.enabled, optional: true),
          Check(id: .secureInput, title: L("Secure keyboard entry"),
                detail: L("A password field or Terminal's Secure Keyboard Entry is on, so keys would slip past. Close it first."),
                ok: !secure, quiet: true),
          Check(id: .lock, title: L("Lock screen"), detail: L("The system's lock function is unavailable"), ok: lock, quiet: true),
        ])
      }
    }
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

  /// The Terminal command that installs the rule, from the folder the app was built in.
  static var sleepRuleCommand: String {
    let repo = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().path
    return "cd '\(repo)' && sudo visudo -cf guard-mode.sudoers && sudo install -m 0440 -o root -g wheel guard-mode.sudoers /etc/sudoers.d/guard-mode"
  }
}

final class PanelModel: ObservableObject {
  enum Page { case main, notReady, push, live }
  @Published var page = Page.main
  @Published var phase = GuardApp.Phase.idle
  @Published var checks: [Check] = []
  @Published var place = Prefs.place { didSet { Prefs.place = place } }
  @Published var note = Prefs.note {
    didSet {
      if note.count > Prefs.noteLimit { note = String(note.prefix(Prefs.noteLimit)) }
      Prefs.note = note
    }
  }
  @Published var volume = Double(Alarm.loudVolume * 100) { didSet { Alarm.loudVolume = Float32(volume / 100) } }
  @Published var testMode = Prefs.testMode { didSet { Prefs.testMode = testMode } }
  @Published var veil = Prefs.veil { didSet { Prefs.veil = veil } }
  @Published var pushOn = Push.enabled {
    didSet {
      Push.enabled = pushOn
      refreshChecks()
    }
  }
  @Published var recent: [Session] = []
  @Published var clips = 0
  @Published var testPush: Bool?  // nil: not sent, or sending
  @Published var sending = false
  @Published var copied: String?
  @Published var confirmReset = false
  @Published var liveLink = Live.link.absoluteString
  var onArm: () -> Void = {}
  var onClose: () -> Void = {}

  var ready: Bool { !checks.isEmpty && checks.allSatisfy { $0.ok || $0.optional } }
  var toFix: Int { checks.filter { !$0.ok && !$0.optional }.count }

  func refresh() {
    place = Prefs.place
    note = Prefs.note
    volume = Double(Alarm.loudVolume * 100)
    testMode = Prefs.testMode
    veil = Prefs.veil
    pushOn = Push.enabled
    recent = History.load()
    clips = Recorder.clips()
    liveLink = Live.link.absoluteString
    copied = nil
    confirmReset = false
    refreshChecks()
  }

  func refreshChecks(prompt: Bool = false) {
    Preflight.run(prompt: prompt) { [weak self] in self?.checks = $0 }
  }

  func arm() {
    guard ready else {
      page = .notReady
      refreshChecks(prompt: true)
      return
    }
    onClose()
    onArm()
  }

  func fix(_ check: Check) {
    switch check.id {
    case .accessibility:
      refreshChecks(prompt: true)
      open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    case .camera:
      if check.askable {
        AVCaptureDevice.requestAccess(for: .video) { _ in DispatchQueue.main.async { self.refreshChecks() } }
      } else {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
      }
    case .sleep:
      copy(Preflight.sleepRuleCommand, as: "sleep")
    case .push:
      page = .push
    default:
      refreshChecks()
    }
  }

  func sendTestPush() {
    sending = true
    testPush = nil
    Push.test { [weak self] ok in
      self?.sending = false
      self?.testPush = ok
    }
  }

  func copy(_ text: String, as what: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    copied = what
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      if self?.copied == what { self?.copied = nil }
    }
  }

  /// First tap asks, the second resets: the old link stops working at once.
  func resetLink() {
    guard confirmReset else { confirmReset = true; return }
    confirmReset = false
    Live.resetLink()
    liveLink = Live.link.absoluteString
  }

  func openRecordings() {
    try? FileManager.default.createDirectory(at: Recorder.folder, withIntermediateDirectories: true)
    NSWorkspace.shared.open(Recorder.folder)
    onClose()
  }

  func open(_ url: String) {
    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
  }
}

// MARK: - views

private let amber = Color(red: 0xF6 / 255, green: 0xB5 / 255, blue: 0x44 / 255)
private let ink = Color(red: 0x2B / 255, green: 0x1A / 255, blue: 0)
private let green = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)

struct PanelView: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    Group {
      switch model.page {
      case .main: MainPage(model: model)
      case .notReady: NotReadyPage(model: model)
      case .push: PushPage(model: model)
      case .live: LivePage(model: model)
      }
    }
    .padding(14)
    .frame(width: 340)
    .animation(.easeInOut(duration: 0.2), value: model.page)
  }
}

private struct MainPage: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if model.phase == .idle {
        armButton
        settings
        Divider()
        VStack(spacing: 2) {
          Row(symbol: "bell.badge", title: L("Phone alerts"), value: model.pushOn ? L("On") : L("Off")) { model.page = .push }
          Row(symbol: "iphone", title: L("Phone page"), value: nil) { model.page = .live }
          Row(symbol: "film", title: L("Recordings"),
              value: L("Only around alarms · %ld", model.clips)) { model.openRecordings() }
        }
        if !model.recent.isEmpty {
          Divider()
          recent
        }
        Divider()
        Button(L("Quit Guard Mode")) { NSApp.terminate(nil) }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .font(.system(size: 12.5))
      } else {
        guarding
      }
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      ShieldGlyph(look: model.phase == .triggered ? .alarm : model.phase == .idle ? .outline : .guarding)
        .frame(width: 26, height: 26)
      VStack(alignment: .leading, spacing: 1) {
        Text("Guard Mode").font(.system(size: 14, weight: .semibold))
        Text(subtitle).font(.system(size: 11.5)).foregroundStyle(.secondary)
      }
      Spacer()
      if model.phase == .idle && !model.checks.isEmpty {
        Button { if !model.ready { model.page = .notReady } } label: {
          Text(model.ready ? L("Ready") : L("Not ready"))
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 20)
            .foregroundStyle(model.ready ? green : amber)
            .background(Capsule().fill((model.ready ? green : amber).opacity(0.16)))
        }
        .buttonStyle(.plain)
      }
    }
  }

  private var subtitle: String {
    switch model.phase {
    case .idle:
      if model.checks.isEmpty { return L("Checking…") }
      if model.ready { return L("Ready · %ld checks passed", model.checks.filter { $0.shown && $0.ok }.count) }
      return model.toFix == 1 ? L("1 thing to fix") : L("%ld things to fix", model.toFix)
    case .arming: return L("Starting…")
    case .armed: return L("Guarding")
    case .triggered: return L("Alarm raised")
    }
  }

  private var armButton: some View {
    Button(action: model.arm) {
      VStack(spacing: 2) {
        Text(L("Start guarding")).font(.system(size: 15, weight: .semibold))
        Text(model.ready ? L("Starts in 5 s · leave it lying still") : L("See what's missing first"))
          .font(.system(size: 11.5))
          .opacity(0.72)
      }
      .foregroundStyle(ink)
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(amber.opacity(model.ready ? 1 : 0.55)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var settings: some View {
    VStack(alignment: .leading, spacing: 11) {
      Picker("", selection: $model.place) {
        ForEach(Place.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      Text(placeHint).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      TextField("", text: $model.note, prompt: Text(L("Note on the screen, e.g. Back in 10 min")))
        .textFieldStyle(.roundedBorder)
      HStack(spacing: 8) {
        Image(systemName: "speaker.wave.2").foregroundStyle(.secondary).frame(width: 18)
        Text(L("Siren")).font(.system(size: 12.5))
        Slider(value: $model.volume, in: 10...100, step: 5)
        Text("\(Int(model.volume))%").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
      }
      Switch(title: L("Test mode"), sub: L("Next run stays silent, then turns itself off"), on: $model.testMode)
      Switch(title: L("Frosted screen"), sub: L("Shows the notice on every screen while guarding"), on: $model.veil)
    }
  }

  private var placeHint: String {
    switch model.place {
    case .library: L("Quiet table: a firm nudge or a lift sounds the alarm")
    case .cafe: L("Busy table: bumps are ignored, carrying it is not")
    case .transit: L("Moving vehicle: only tilt, the lid, the charger and touch count")
    }
  }

  private var recent: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(L("Recent")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
      ForEach(Array(model.recent.prefix(3).enumerated()), id: \.offset) { _, s in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Circle().fill(s.trigger == nil ? green : Color(red: 1, green: 0x4D / 255, blue: 0x55 / 255)).frame(width: 6, height: 6)
          Text(s.line).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
          Spacer(minLength: 4)
          Text(Clock.when(s.armed)).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize()
        }
      }
    }
  }

  private var guarding: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(model.phase == .triggered ? L("Alarm raised") : L("This Mac is guarded"))
        .font(.system(size: 15, weight: .semibold))
      Text(L("Rest a finger on Touch ID, or unlock the Mac, to stop"))
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(amber.opacity(0.14)))
  }
}

private struct NotReadyPage: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Back(title: L("Before guarding")) { model.page = .main }
      Text(L("Guard Mode starts once everything marked below is fixed."))
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 0) {
        ForEach(model.checks.filter(\.shown)) { check in
          CheckRow(check: check, copied: model.copied == "sleep" && check.id == .sleep) { model.fix(check) }
          if check.id != model.checks.filter(\.shown).last?.id { Divider().padding(.leading, 30) }
        }
      }
      HStack {
        Button(L("Check again")) { model.refreshChecks() }
        Spacer()
        Button(L("Start guarding")) { model.arm() }
          .disabled(!model.ready)
      }
      .controlSize(.small)
    }
  }
}

private struct CheckRow: View {
  let check: Check
  let copied: Bool
  let fix: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: check.ok ? "checkmark.circle.fill" : check.optional ? "circle.dashed" : "exclamationmark.circle.fill")
        .foregroundStyle(check.ok ? green : check.optional ? Color.secondary : amber)
        .font(.system(size: 15))
        .frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(check.title).font(.system(size: 12.5, weight: .medium))
          if check.optional { Text(L("optional")).font(.system(size: 10.5)).foregroundStyle(.tertiary) }
        }
        Text(check.detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 6)
      if let label = fixLabel {
        Button(label, action: fix).controlSize(.small)
      }
    }
    .padding(.vertical, 8)
  }

  private var fixLabel: String? {
    guard !check.ok else { return nil }
    switch check.id {
    case .accessibility: return L("Open Settings")
    case .camera: return check.askable ? L("Allow") : L("Open Settings")
    case .sleep: return copied ? L("Copied") : L("Copy command")
    case .push: return L("Set up")
    default: return nil
    }
  }
}

private struct PushPage: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Back(title: L("Phone alerts")) { model.page = .main }
      Switch(title: L("Send alerts to my phone"), sub: L("An alarm sends what happened and a photo"), on: $model.pushOn)
      if model.pushOn {
        HStack(alignment: .top, spacing: 14) {
          QRView(text: "https://ntfy.sh/" + Push.topic)
          VStack(alignment: .leading, spacing: 7) {
            Step(n: 1, text: L("Install the free ntfy app"))
            Step(n: 2, text: L("Scan this code, or paste the topic under + in ntfy"))
            Step(n: 3, text: L("Send a test below"))
          }
        }
        HStack {
          Button(model.copied == "topic" ? L("Copied") : L("Copy topic")) { model.copy(Push.topic, as: "topic") }
          Spacer()
          if model.sending {
            ProgressView().controlSize(.small)
          } else if let ok = model.testPush {
            Text(ok ? L("Sent. Check your phone.") : L("Couldn't send. Check the network."))
              .font(.system(size: 11.5))
              .foregroundStyle(ok ? green : amber)
          }
          Button(L("Send a test"), action: model.sendTestPush).disabled(model.sending)
        }
        .controlSize(.small)
        Text(L("Alerts go through ntfy.sh. The topic name is the only key, and photos are kept there for 3 hours."))
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct LivePage: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Back(title: L("Phone page")) { model.page = .main }
      HStack(alignment: .top, spacing: 14) {
        QRView(text: model.liveLink)
        VStack(alignment: .leading, spacing: 7) {
          Text(L("Open this on your phone and keep it.")).font(.system(size: 12.5, weight: .medium))
          Text(L("Before an alarm it only shows whether this Mac is guarded. After one it shows the camera, the photos and what happened."))
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Text(L("The page can only watch. It can't control this Mac."))
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
      HStack {
        Button(model.copied == "link" ? L("Copied") : L("Copy link")) { model.copy(model.liveLink, as: "link") }
        Spacer()
        Button(model.confirmReset ? L("Tap again: the old link stops working") : L("Reset link"), action: model.resetLink)
          .foregroundStyle(model.confirmReset ? Color.red : Color.primary)
      }
      .controlSize(.small)
    }
  }
}

private struct Row: View {
  let symbol: String
  let title: String
  let value: String?
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
        Text(title).font(.system(size: 13))
        Spacer()
        if let value { Text(value).font(.system(size: 12)).foregroundStyle(.secondary) }
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 6)
      .frame(height: 30)
      .background(RoundedRectangle(cornerRadius: 7).fill(hover ? Color.primary.opacity(0.07) : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
  }
}

private struct Switch: View {
  let title: String
  let sub: String
  @Binding var on: Bool

  var body: some View {
    Toggle(isOn: $on) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 12.5))
        Text(sub).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
    .toggleStyle(.switch)
    .controlSize(.small)
  }
}

private struct Back: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
        Text(title).font(.system(size: 14, weight: .semibold))
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct Step: View {
  let n: Int
  let text: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Text("\(n)")
        .font(.system(size: 10.5, weight: .bold))
        .foregroundStyle(ink)
        .frame(width: 16, height: 16)
        .background(Circle().fill(amber))
      Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct QRView: View {
  let text: String

  var body: some View {
    Group {
      if let image = QR.image(text) {
        Image(nsImage: image).interpolation(.none).resizable()
      } else {
        Color.secondary.opacity(0.2)
      }
    }
    .frame(width: 112, height: 112)
    .padding(6)
    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
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
