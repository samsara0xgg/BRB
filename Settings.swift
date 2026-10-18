import AppKit
import SwiftUI

/// Settings' four tabs.
enum SettingsTab: String, CaseIterable {
  case general, phone, recordings, checks

  var title: String {
    switch self {
    case .general: L("General")
    case .phone: L("Phone")
    case .recordings: L("Recordings")
    case .checks: L("Checks")
    }
  }

  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .phone: "iphone"
    case .recordings: "video"
    case .checks: "checkmark.shield"
    }
  }
}

/// What isn't needed on the way out, in a window of its own as a Mac app's settings are (audit A1):
/// the siren, test mode and the frosted screen; the phone; the recordings; every check. It shares
/// the panel's model, so the two never disagree. The window takes each pane's height, its top edge
/// staying put, as System Settings' panes do.
final class SettingsWindow: NSObject, NSToolbarDelegate, NSWindowDelegate {
  static let width: CGFloat = 560
  let model: PanelModel
  private var window: NSWindow?
  private var poll: Timer?
  /// Off while the window opens, so it appears at its size instead of growing into it.
  private var animates = false

  init(model: PanelModel) {
    self.model = model
    super.init()
  }

  var isVisible: Bool { window?.isVisible == true }

  func show(_ tab: SettingsTab) {
    let w = window ?? make()
    model.refresh()
    select(tab, in: w)
    if !w.isVisible {
      animates = false
      resize(w, to: SettingsPane.height(model: model, tab: tab), animate: false)
      w.center()
    }
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
    start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      if self?.isVisible == true { self?.animates = true }
    }
  }

  func close() {
    window?.close()
  }

  private func make() -> NSWindow {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 380),
                     styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.isReleasedWhenClosed = false
    w.delegate = self
    let toolbar = NSToolbar(identifier: "BRBSettings")
    toolbar.delegate = self
    toolbar.displayMode = .iconAndLabel
    toolbar.allowsUserCustomization = false
    w.toolbar = toolbar
    w.toolbarStyle = .preference
    let host = NSHostingView(rootView: SettingsRoot(model: model) { [weak self] tab, height in self?.fit(tab, height) })
    host.sizingOptions = []  // the window follows the pane by hand, so it can animate
    w.contentView = host
    w.center()
    window = w
    return w
  }

  private func select(_ tab: SettingsTab, in w: NSWindow) {
    w.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
    w.title = tab.title
    guard model.settingsTab != tab else { return }
    if w.isVisible {
      withAnimation(Theme.out(0.3)) { model.settingsTab = tab }
    } else {
      model.settingsTab = tab
    }
  }

  /// A pane's height changed: a tab picked, alerts switched on, the reset line opened. Only the
  /// shown tab's pane counts: one on its way out, or the one first laid out, reports too.
  private func fit(_ tab: SettingsTab, _ height: CGFloat) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let w = window, tab == model.settingsTab else { return }
      resize(w, to: height, animate: animates && w.isVisible)
    }
  }

  /// Makes the pane area `height` tall, the top edge staying put. Measured against the content view
  /// itself, so the toolbar's height never needs knowing; kept clear of the Dock and the menu bar.
  private func resize(_ w: NSWindow, to height: CGFloat, animate: Bool) {
    guard let content = w.contentView else { return }
    let delta = ceil(max(height, 120)) - content.frame.height
    guard abs(delta) > 0.5 else { return }
    var f = w.frame
    f.origin.y -= delta
    f.size.height += delta
    if let visible = (w.screen ?? NSScreen.main)?.visibleFrame {
      f.origin.y = min(max(f.origin.y, visible.minY), visible.maxY - f.height)
    }
    w.setFrame(f, display: true, animate: animate)
  }

  /// While open: the checks once a second, as the panel does, so a fix made in System Settings
  /// ticks off here too.
  private func start() {
    poll?.invalidate()
    let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.model.poll() }
    RunLoop.main.add(t, forMode: .common)
    poll = t
  }

  func windowWillClose(_ notification: Notification) {
    poll?.invalidate()
    poll = nil
    animates = false
    model.cancelReset()
    model.pairing.end()
  }

  // MARK: toolbar

  private var tabs: [NSToolbarItem.Identifier] { SettingsTab.allCases.map { NSToolbarItem.Identifier($0.rawValue) } }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabs }
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabs }
  func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabs }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    guard let tab = SettingsTab(rawValue: id.rawValue) else { return nil }
    let item = NSToolbarItem(itemIdentifier: id)
    item.label = tab.title
    item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
    item.target = self
    item.action = #selector(pick(_:))
    return item
  }

  @objc private func pick(_ item: NSToolbarItem) {
    guard let tab = SettingsTab(rawValue: item.itemIdentifier.rawValue), let w = window else { return }
    select(tab, in: w)
  }
}

/// The selected pane, cross-fading into the next, with its height handed to the window.
struct SettingsRoot: View {
  @ObservedObject var model: PanelModel
  /// A pane's height, with the tab it belongs to.
  var fit: (SettingsTab, CGFloat) -> Void = { _, _ in }

  var body: some View {
    let tab = model.settingsTab
    ZStack(alignment: .top) {
      SettingsPane(model: model, tab: tab)
        .background(GeometryReader { g in
          Color.clear
            .onAppear { fit(tab, g.size.height) }
            .onChange(of: g.size.height) { _, h in fit(tab, h) }
        })
        .id(tab)
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
    }
    .frame(width: SettingsWindow.width)
    .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)  // while the window grows, the pane hangs from the top
  }
}

/// One tab's content at its natural height.
struct SettingsPane: View {
  @ObservedObject var model: PanelModel
  let tab: SettingsTab

  var body: some View {
    Group {
      switch tab {
      case .general: GeneralPane(model: model)
      case .phone: PhonePane(model: model)
      case .recordings: RecordingsPane(model: model)
      case .checks: ChecksPane(model: model)
      }
    }
    .padding(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))
    .frame(width: SettingsWindow.width)
    .fixedSize(horizontal: false, vertical: true)
  }

  /// The height a pane takes, for sizing the window before it shows.
  static func height(model: PanelModel, tab: SettingsTab) -> CGFloat {
    NSHostingController(rootView: SettingsPane(model: model, tab: tab))
      .sizeThatFits(in: CGSize(width: SettingsWindow.width, height: 4000)).height
  }
}

// MARK: - panes

private struct GeneralPane: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      SettingsGroup {
        VolumeRow(model: model)
        if model.confirmPreview {
          RowDivider()
          PreviewConfirm(model: model)
            .transition(.opacity.combined(with: .offset(y: -4)))
        }
        RowDivider()
        SwitchRow(title: L("Test mode"), sub: L("Next run stays silent, then turns itself off"), on: $model.testMode, striped: true)
        RowDivider()
        SwitchRow(title: L("Frosted screen"), sub: L("Shows the notice on every screen while guarding"), on: $model.veil)
      }
      SettingsGroup {
        SettingsRow(title: L("How it works"), sub: L("Three cards on what Back in 5 does")) {
          Button(L("Show again"), action: model.onIntro)
            .controlSize(.small)
        }
      }
      Text(verbatim: "Back in 5 · \(version)")
        .font(Theme.label)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }
  }

  private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
}

/// The siren's volume on a slider of its own, the full width of the row, under its title and
/// "Preview…". The ellipsis says the button asks first: see `PreviewConfirm`.
private struct VolumeRow: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L("Siren volume"))
            .font(Theme.body)
          Text(L("The siren plays on the built-in speakers"))
            .font(Theme.label)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 12)
        Button(action: model.askPreview) {
          HStack(spacing: 5) {
            Meter(model: model)
            Text(L("Preview…"))
          }
          .fixedSize()
        }
        .controlSize(.small)
        .disabled(model.phase != .idle || model.confirmPreview)
      }
      HStack(spacing: 8) {
        Image(systemName: "speaker.wave.1.fill")
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
        Slider(value: Binding(get: { model.volume }, set: { model.volume = ($0 / 5).rounded() * 5 }), in: 10...100)
          .controlSize(.small)
          .tint(Theme.amberDeep)
        Image(systemName: "speaker.wave.3.fill")
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
        Text(verbatim: "\(Int(model.volume))%")
          .font(Theme.caption)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 36, alignment: .trailing)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }
}

/// What "Preview…" is about to do, before it does it: the siren at the set volume, on the
/// built-in speakers even with headphones on. Play, or Cancel (esc); it folds away by itself.
private struct PreviewConfirm: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "speaker.wave.3.fill")
        .font(.system(size: 12))
        .foregroundStyle(Theme.amberDeep)
      Text(L("Sounds the siren at %d%% for under a second, even with headphones on.", Int(model.volume)))
        .font(Theme.caption)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button(L("Cancel"), action: model.cancelPreview)
        .keyboardShortcut(.cancelAction)
      Button(L("Play"), action: model.preview)
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }
    .controlSize(.small)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .frame(minHeight: 44)
    .background(Theme.amber.opacity(0.08))
  }
}

/// Seven bars that dance at the set volume while the preview plays (audit B4).
private struct Meter: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    TimelineView(.animation(minimumInterval: nil, paused: !model.previewing)) { tl in
      let t = tl.date.timeIntervalSince(model.previewAt)
      HStack(spacing: 1.5) {
        ForEach(0..<7, id: \.self) { i in
          Capsule()
            .fill(model.previewing ? Theme.amberDeep : Color.secondary.opacity(0.55))
            .frame(width: 2, height: 3 + 9 * level(i, t))
        }
      }
      .frame(height: 12)
    }
    .animation(.easeOut(duration: 0.2), value: model.previewing)
  }

  private func level(_ i: Int, _ t: Double) -> Double {
    guard model.previewing else { return [0.2, 0.35, 0.5, 0.35, 0.5, 0.35, 0.2][i] }
    let wave = 0.5 + 0.5 * sin(t * 40 + Double(i) * 1.7)
    return model.volume / 100 * (0.45 + 0.55 * wave)
  }
}

/// Pairing the iPhone app: "Pair iPhone…" shows a code, as a QR code and as six digits, that renews
/// itself while this pane is open. Once a phone has claimed it, the pane says so and offers to undo it.
private struct IPhoneGroup: View {
  @ObservedObject var pairing: PairingModel
  @AppStorage("phonePaired") private var paired = false
  @AppStorage("phoneName") private var name = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsGroup {
        if pairing.shown {
          if let offer = pairing.offer {
            code(offer)
              .transition(.opacity)
          } else if pairing.failed {
            SettingsRow(title: L("Couldn't make a code"), sub: L("Check the network and try again.")) {
              HStack(spacing: 8) {
                Button(L("Done"), action: pairing.end)
                Button(L("Try again"), action: pairing.begin)
              }
              .controlSize(.small)
            }
          } else {
            ProgressView()
              .controlSize(.small)
              .frame(maxWidth: .infinity, minHeight: 44)
          }
        } else if paired {
          SettingsRow(title: name.isEmpty ? L("An iPhone is paired") : L("Paired with %@", name),
                      sub: L("It can stop the siren, disarm and start guarding.")) {
            Button(L("Pair iPhone…"), action: pairing.begin)
              .controlSize(.small)
          }
          RowDivider()
          ZStack {
            if pairing.confirmUnpair {
              confirm.transition(.opacity.combined(with: .offset(y: 4)))
            } else {
              unpairRow.transition(.opacity)
            }
          }
          .controlSize(.small)
        } else {
          SettingsRow(title: L("Back in 5 on your iPhone"), sub: L("Stop the siren, disarm or start guarding from your phone, and see the history.")) {
            Button(L("Pair iPhone…"), action: pairing.begin)
              .controlSize(.small)
          }
        }
      }
      .animation(Theme.out(0.3), value: pairing.shown)
      .animation(Theme.out(0.3), value: paired)
      if pairing.shown, pairing.offer != nil {
        Footnote(L("The code works once and renews itself while this is open."))
      }
    }
    .onDisappear { pairing.end() }
  }

  private func code(_ offer: PairOffer) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 16) {
        QRView(text: offer.link)
          .id(offer.qr)
          .transition(.opacity)
        VStack(alignment: .leading, spacing: 10) {
          Step(n: 1, text: L("Open the Back in 5 app on your iPhone"))
          Step(n: 2, text: L("Scan this code, or type the six digits"))
          Text(verbatim: offer.spaced)
            .font(.system(size: 26, weight: .semibold, design: .monospaced))
            .textSelection(.enabled)
          Text(L("Expires in %@", String(format: "%ld:%02ld", pairing.remaining / 60, pairing.remaining % 60)))
            .font(Theme.label)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
        Spacer(minLength: 0)
      }
      .padding(12)
      RowDivider()
      HStack {
        Spacer(minLength: 8)
        Button(L("Done"), action: pairing.end)
      }
      .controlSize(.small)
      .padding(.horizontal, 12)
      .frame(minHeight: 44)
    }
  }

  private var unpairRow: some View {
    HStack {
      Spacer(minLength: 8)
      Button(L("Unpair all phones…"), action: pairing.askUnpair)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 44)
  }

  /// "Unpair all phones…" says what happens before it happens, as "Reset link…" does.
  private var confirm: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .symbolRenderingMode(.palette)
        .foregroundStyle(Color.white, Theme.red)
        .font(.system(size: 13))
      Text(L("Every paired iPhone and the phone page link stop working at once."))
        .font(Theme.caption)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button(L("Cancel"), action: pairing.cancelUnpair)
      Button(L("Unpair"), action: pairing.unpair)
        .buttonStyle(.borderedProminent)
        .tint(Theme.redDeep)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 44)
    .background(Theme.red.opacity(0.08))
  }
}

private struct PhonePane: View {
  @ObservedObject var model: PanelModel
  @AppStorage("phonePaired") private var paired = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionHead(L("iPhone app"))
      IPhoneGroup(pairing: model.pairing)
      SectionHead(L("Phone page"))
        .padding(.top, 12)
      SettingsGroup {
        HStack(alignment: .top, spacing: 16) {
          QRView(text: model.liveLink)
            .id(model.liveLink)
            .transition(.opacity)
          VStack(alignment: .leading, spacing: 6) {
            Text(L("Open this on your phone and keep it."))
              .font(.system(size: 13, weight: .medium))
            Text(L("Before an alarm it only shows whether this Mac is guarded. After one it shows the camera, the photos and what happened."))
              .font(Theme.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Label(L("The page can only watch. It can't control this Mac."), systemImage: "eye")
              .font(Theme.label)
              .foregroundStyle(.tertiary)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.top, 2)
          }
          .padding(.top, 6)
        }
        .padding(12)
        RowDivider()
        ZStack {
          if model.confirmReset {
            confirm.transition(.opacity.combined(with: .offset(y: 4)))
          } else {
            actions.transition(.opacity)
          }
        }
        .controlSize(.small)
      }
    }
  }

  private var actions: some View {
    HStack(spacing: 10) {
      Button(model.copied == "link" ? L("Copied") : L("Copy link")) { model.copy(model.liveLink, as: "link") }
      if model.linkReset {
        Label(L("New link made"), systemImage: "checkmark")
          .font(Theme.label)
          .foregroundStyle(Theme.greenText)
          .transition(.opacity)
      }
      Spacer(minLength: 8)
      Button(L("Reset link…"), action: model.askReset)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 44)
  }

  /// "Reset link…" says what happens before it happens (audit B3).
  private var confirm: some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .symbolRenderingMode(.palette)
        .foregroundStyle(Color.white, Theme.red)
        .font(.system(size: 13))
      Text(paired ? L("The old link stops working at once. Paired iPhones are unpaired.") : L("The old link stops working at once."))
        .font(Theme.caption)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button(L("Cancel"), action: model.cancelReset)
        .keyboardShortcut(.cancelAction)
      Button(L("Reset"), action: model.resetLink)
        .buttonStyle(.borderedProminent)
        .tint(Theme.redDeep)
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 44)
    .background(Theme.red.opacity(0.08))
  }
}

private struct RecordingsPane: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SettingsGroup {
        if let camera = model.check(.camera), !camera.ok {
          SettingsRow(title: L("Camera"), sub: camera.detail) {
            if !camera.optional {
              Button(camera.askable ? L("Allow") : L("Open Settings")) { model.fix(camera) }
                .controlSize(.small)
            }
          }
          RowDivider()
        }
        SettingsRow(title: L("Only around alarms"), sub: L("The 10 seconds before an alarm and what follows. Faces behind the person are blurred.")) {
          EmptyView()
        }
        RowDivider()
        SettingsRow(title: L("Kept for")) {
          Text(L("7 days, 20 GB at most"))
            .font(Theme.caption)
            .foregroundStyle(.secondary)
        }
      }
      HStack(alignment: .firstTextBaseline) {
        SectionHead(heading)
        Spacer(minLength: 8)
        Button(L("Open Recordings Folder")) { model.reveal(nil) }
          .controlSize(.small)
      }
      .padding(.top, 12)
      if !model.clips.isEmpty {
        SettingsGroup {
          ForEach(Array(model.clips.prefix(6).enumerated()), id: \.element.id) { i, clip in
            if i > 0 { RowDivider() }
            ClipRow(clip: clip) { model.reveal(clip.url.lastPathComponent) }
          }
        }
      }
    }
  }

  private var heading: String {
    switch model.clips.count {
    case 0: L("No recordings yet")
    case 1: L("1 recording")
    default: L("%ld recordings", model.clips.count)
    }
  }
}

private struct ClipRow: View {
  let clip: Clip
  let reveal: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: reveal) {
      HStack(spacing: 10) {
        Image(systemName: "video.fill")
          .font(.system(size: 11))
          .foregroundStyle(alarmed ? Theme.red : Color.secondary)
          .frame(width: 26, height: 26)
          .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(alarmed ? Theme.red.opacity(0.15) : Theme.fill))
        VStack(alignment: .leading, spacing: 1) {
          Text(clip.session?.title ?? clip.url.deletingPathExtension().lastPathComponent)
            .font(Theme.body)
            .lineLimit(1)
            .truncationMode(.middle)
          Text(detail)
            .font(Theme.label)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        Image(systemName: "arrow.up.forward")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.tertiary)
          .opacity(hover ? 1 : 0)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(hover ? Theme.fill : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
    .animation(.easeOut(duration: 0.15), value: hover)
    .help(L("Show in Finder"))
  }

  private var alarmed: Bool { clip.session.map { $0.alarmed && !$0.test } ?? false }

  private var detail: String {
    var parts = [Clock.when(clip.date)]
    if clip.bytes > 0 { parts.append(ByteCountFormatter.string(fromByteCount: clip.bytes, countStyle: .file)) }
    if clip.session?.test == true { parts.append(L("Test · silent")) }
    return parts.joined(separator: " · ")
  }
}

private struct ChecksPane: View {
  @ObservedObject var model: PanelModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SettingsGroup {
        ForEach(Array(model.checks.filter(\.shown).enumerated()), id: \.element.id) { i, check in
          if i > 0 { RowDivider() }
          CheckRow(check: check, busy: model.installing && check.id == .sleep) { model.fix(check) }
        }
      }
      .animation(Theme.resize, value: model.checks.map(\.ok))
      HStack(spacing: 8) {
        if model.locked {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(Theme.amberDeep)
          Text(model.toFix == 1 ? L("1 thing to fix") : L("%ld things to fix", model.toFix))
            .foregroundStyle(Theme.warn)
        } else if !model.checks.isEmpty {
          Image(systemName: "checkmark.seal.fill")
            .foregroundStyle(Theme.green)
          Text(L("All set"))
            .foregroundStyle(Theme.greenText)
        }
        Spacer(minLength: 8)
        Button(action: model.checkAgain) {
          HStack(spacing: 5) {
            if model.checking { ProgressView().controlSize(.mini) }
            Text(L("Check again"))
          }
        }
        .controlSize(.small)
        .disabled(model.checking)
      }
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 4)
    }
  }
}

private struct CheckRow: View {
  let check: Check
  let busy: Bool
  let fix: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      icon
        .font(.system(size: 16))
        .frame(width: 20, height: 20)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: check.ok)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(check.title)
            .font(Theme.body)
          if check.optional {
            Text(L("optional"))
              .font(.system(size: 10.5))
              .foregroundStyle(.tertiary)
          }
        }
        Text(check.detail)
          .font(Theme.label)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 10)
      if !check.ok, let label {
        Button(action: fix) {
          HStack(spacing: 5) {
            if busy { ProgressView().controlSize(.mini) }
            Text(label)
          }
        }
        .controlSize(.small)
        .disabled(busy)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .frame(minHeight: 44)
  }

  @ViewBuilder private var icon: some View {
    if check.ok {
      Image(systemName: "checkmark.circle.fill")
        .symbolRenderingMode(.palette)
        .foregroundStyle(Color.white, Theme.green)
        .transition(.scale(scale: 0.4).combined(with: .opacity))
    } else if check.optional {
      Image(systemName: "circle.dashed")
        .foregroundStyle(.tertiary)
        .transition(.opacity)
    } else {
      Image(systemName: "exclamationmark.circle.fill")
        .symbolRenderingMode(.palette)
        .foregroundStyle(Theme.ink, Theme.amberDeep)
        .transition(.opacity)
    }
  }

  private var label: String? {
    switch check.id {
    case .accessibility: L("Open Settings")
    case .camera: check.optional ? nil : check.askable ? L("Allow") : L("Open Settings")
    case .sleep: busy ? L("Installing…") : L("Install")
    case .push: L("Set up")
    default: nil
    }
  }
}

// MARK: - pieces

/// A rounded group of rows, as in System Settings.
private struct SettingsGroup<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.separator, lineWidth: 0.5))
  }
}

private struct RowDivider: View {
  var body: some View {
    Rectangle()
      .fill(Theme.separator)
      .frame(height: 0.5)
      .padding(.leading, 12)
  }
}

private struct SettingsRow<Trailing: View>: View {
  let title: String
  var sub: String? = nil
  @ViewBuilder let trailing: Trailing

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(Theme.body)
        if let sub {
          Text(sub)
            .font(Theme.label)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 12)
      trailing
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(minHeight: 44)
  }
}

private struct SwitchRow: View {
  let title: String
  let sub: String
  @Binding var on: Bool
  var striped = false

  var body: some View {
    Toggle(isOn: $on) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(Theme.body)
        Text(sub)
          .font(Theme.label)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .toggleStyle(AmberSwitch(striped: striped))
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(minHeight: 44)
  }
}

private struct SectionHead: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(.system(size: 13, weight: .semibold))
      .padding(.horizontal, 4)
  }
}

private struct Footnote: View {
  let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .font(Theme.label)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 4)
  }
}
