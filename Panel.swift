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
                detail: !camera ? L("No built-in camera: an alarm won't be recorded")
                  : status == .authorized ? L("Films only around an alarm")
                  : status == .notDetermined ? L("Allow it so an alarm can be recorded") : L("Turned off for GuardMode in System Settings"),
                ok: camera && status == .authorized, optional: !camera, askable: camera && status == .notDetermined),
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
private let amberDeep = Color(red: 0xF0 / 255, green: 0xA5 / 255, blue: 0x3A / 255)
/// Sessions with an alarm in the recent list: dark amber on light, light amber on dark.
private let warn = Color(nsColor: NSColor(name: nil) { appearance in
  appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    ? NSColor(srgbRed: 1, green: 0xC2 / 255, blue: 0x61 / 255, alpha: 1)
    : NSColor(srgbRed: 0xB8 / 255, green: 0x6B / 255, blue: 0, alpha: 1)
})

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
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Text(L("Place")).font(.system(size: 13))
            Spacer(minLength: 8)
            PlacePicker(selection: $model.place)
          }
          Text(placeHint).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          NoteField(text: $model.note)
        }
        .padding(.horizontal, 6)
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            Text(L("Siren volume")).font(.system(size: 13))
            Spacer(minLength: 8)
            Slider(value: Binding(get: { model.volume }, set: { model.volume = ($0 / 5).rounded() * 5 }), in: 10...100)
              .controlSize(.small)
              .tint(amberDeep)
              .frame(width: 118)
            Text("\(Int(model.volume))%").font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
          }
          Switch(title: L("Test mode"), sub: L("Next run stays silent, then turns itself off"), on: $model.testMode)
          Switch(title: L("Frosted screen"), sub: L("Shows the notice on every screen while guarding"), on: $model.veil)
        }
        .padding(.horizontal, 6)
        VStack(spacing: 0) {
          Row(title: L("Phone alerts"), value: model.pushOn ? L("On") : L("Off")) { model.page = .push }
          Row(title: L("Phone page"), value: L("After an alarm only")) { model.page = .live }
          Row(title: L("Recordings"), value: L("Only around alarms · %ld", model.clips)) { model.openRecordings() }
        }
        if !model.recent.isEmpty {
          Divider()
          recent
        }
        Divider()
        Button(L("Quit Guard Mode")) { NSApp.terminate(nil) }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .font(.system(size: 12))
          .padding(.horizontal, 6)
      } else {
        guarding
      }
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      ZStack {
        Circle().fill(LinearGradient(colors: [Color(red: 0x2B / 255, green: 0x3A / 255, blue: 0x6B / 255), Color(red: 0x13 / 255, green: 0x1A / 255, blue: 0x33 / 255)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
        ShieldGlyph(look: glyph).frame(width: 20, height: 20)
      }
      .frame(width: 36, height: 36)
      VStack(alignment: .leading, spacing: 1) {
        Text("Guard Mode").font(.system(size: 14.5, weight: .semibold))
        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 6)
      if model.phase == .idle && !model.checks.isEmpty {
        Button { if !model.ready { model.page = .notReady } } label: {
          HStack(spacing: 6) {
            Circle().fill(model.ready ? green : amberDeep).frame(width: 8, height: 8)
            Text(model.ready ? L("Ready") : L("Not ready")).font(.system(size: 11.5)).foregroundStyle(.secondary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 4)
  }

  private var glyph: ShieldGlyph.Look {
    switch model.phase {
    case .triggered: .alarm
    case .idle: model.ready ? .guarding : .outline
    default: .guarding
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
      VStack(spacing: 1) {
        Text(L("Start guarding")).font(.system(size: 16, weight: .semibold))
        Text(model.ready ? L("Starts in 5 s · leave it lying still") : L("See what's missing first"))
          .font(.system(size: 11.5))
          .opacity(0.72)
      }
      .foregroundStyle(model.ready ? ink : Color.secondary)
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .background {
        if model.ready {
          Capsule()
            .fill(LinearGradient(colors: [Color(red: 1, green: 0xCF / 255, blue: 0x6B / 255), amberDeep], startPoint: .top, endPoint: .bottom))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0)], startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: Color(red: 220 / 255, green: 140 / 255, blue: 20 / 255).opacity(0.35), radius: 8, y: 6)
        } else {
          Capsule().fill(Color.primary.opacity(0.055))
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(Pressable())
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
      Text(L("Recent")).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.tertiary)
      ForEach(Array(model.recent.prefix(3).enumerated()), id: \.offset) { _, s in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(Clock.when(s.armed))
            .font(.system(size: 11.5, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 108, alignment: .leading)
          Text(s.line)
            .font(.system(size: 12.5))
            .foregroundStyle(s.trigger == nil ? Color.primary : warn)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .padding(.horizontal, 6)
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
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(amber.opacity(0.14)))
  }
}

/// Library, café, on the go: design A's capsule switcher, a white knob on a quiet well.
private struct PlacePicker: View {
  @Binding var selection: Place

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Place.allCases, id: \.self) { place in
        Button { selection = place } label: {
          Text(place.title)
            .font(.system(size: 12.5, weight: place == selection ? .semibold : .regular))
            .foregroundStyle(place == selection ? Color(red: 0x12 / 255, green: 0x18 / 255, blue: 0x26 / 255) : Color.primary)
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background {
              if place == selection {
                Capsule().fill(Color.white).shadow(color: .black.opacity(0.14), radius: 1.5, y: 1)
              }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(place == selection ? .isSelected : [])
      }
    }
    .padding(2)
    .background(Capsule().fill(Color.primary.opacity(0.055)))
    .animation(.easeOut(duration: 0.15), value: selection)
    .fixedSize()
  }
}

private struct NoteField: View {
  @Binding var text: String
  @FocusState private var focused: Bool

  var body: some View {
    TextField("", text: $text, prompt: Text(L("Note on the screen, e.g. Back in 10 min")))
      .textFieldStyle(.plain)
      .font(.system(size: 13))
      .focused($focused)
      .padding(.horizontal, 10)
      .frame(height: 32)
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.055)))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(amberDeep, lineWidth: 2).opacity(focused ? 1 : 0))
  }
}

private struct Pressable: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
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
    case .camera: return check.optional ? nil : check.askable ? L("Allow") : L("Open Settings")
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
  let title: String
  let value: String?
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Text(title).font(.system(size: 13))
        Spacer(minLength: 8)
        if let value { Text(value).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1) }
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 6)
      .frame(height: 34)
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hover ? Color.primary.opacity(0.055) : .clear))
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
        Text(title).font(.system(size: 13))
        Text(sub).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
    .toggleStyle(AmberSwitch())
  }
}

/// Design A's switch: the label on the left, the switch always at the trailing edge, amber stripes
/// when on.
private struct AmberSwitch: ToggleStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 10) {
      configuration.label
      Spacer(minLength: 0)
      Button { configuration.isOn.toggle() } label: {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
          Capsule()
            .fill(configuration.isOn ? amberDeep : Color.primary.opacity(0.08))
            .overlay {
              if configuration.isOn { Stripes().clipShape(Capsule()) }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
          Circle()
            .fill(Color.white)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            .frame(width: 20, height: 20)
            .padding(2)
        }
        .frame(width: 40, height: 24)
        .contentShape(Capsule())
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
      }
      .buttonStyle(.plain)
    }
    .accessibilityElement(children: .combine)
    .accessibilityValue(configuration.isOn ? L("On") : L("Off"))
  }
}

/// 6 pt bands at 45°, 12 pt apart: the CSS repeating-linear-gradient(135deg) of the design.
private struct Stripes: View {
  var body: some View {
    Canvas { ctx, size in
      var p = Path()
      var x = -size.height
      while x < size.width + size.height {
        p.move(to: CGPoint(x: x, y: size.height))
        p.addLine(to: CGPoint(x: x + size.height, y: 0))
        x += 12 * CGFloat(2).squareRoot()
      }
      ctx.stroke(p, with: .color(Color(red: 0xF6 / 255, green: 0xBE / 255, blue: 0x5E / 255)), lineWidth: 6)
    }
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
