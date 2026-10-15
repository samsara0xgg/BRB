import Network
import SwiftUI
import UIKit

/// Watches whether the phone has a network at all, so the pages can say "your phone is offline".
final class NetworkMonitor {
  private let monitor = NWPathMonitor()
  var onChange: (@MainActor (Bool) -> Void)?

  func start() {
    monitor.pathUpdateHandler = { [weak self] path in
      let offline = path.status != .satisfied
      Task { @MainActor in self?.onChange?(offline) }
    }
    monitor.start(queue: DispatchQueue(label: "brb.network"))
  }
}

extension AppStore {
  /// What the pages should pretend, for screenshots (`-pstate loading|error|empty|offline`), else the phone's real state.
  var pageState: String? { launch.pageState ?? (phoneOffline ? "offline" : nil) }

  func addMac() {
    onboarding = Onboarding(step: .scan, extra: true)
  }

  func refreshAll() async {
    for m in macs { await backend.refresh(m) }
    loadFailed = !macs.isEmpty && macs.allSatisfy { $0.link == .down && $0.snapshot.lastSeen == 0 }
  }

  /// "Turn on" in the yellow bar: ask if we never asked, otherwise send the owner to Settings.
  func fixNotifications() {
    if notif == .unknown {
      Task { _ = await pushRegistrar.requestAuthorization(critical: criticalAlerts) }
    } else if let url = URL(string: UIApplication.openSettingsURLString) {
      UIApplication.shared.open(url)
    }
  }

  func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
  }

  // MARK: Photos

  func photoImages(of mac: MacModel, _ photos: [Ms]) async -> [UIImage] {
    var out: [UIImage] = []
    for ms in photos {
      if let image = await PhotoCache.shared.image(ms, of: mac, via: backend) { out.append(image) }
    }
    return out
  }

  func savePhotos(of mac: MacModel, photos: [Ms]) async {
    guard !photos.isEmpty else {
      show(t("noPhotos"), "photo")
      return
    }
    let images = await photoImages(of: mac, photos)
    guard !images.isEmpty else {
      show(failureText("net"), "exclamationmark.triangle")
      return
    }
    if await PhotoExport.save(images) {
      show(t("savedPhotos", tn("n_photos", images.count)), "square.and.arrow.down")
    } else {
      show(t("err_photos"), "exclamationmark.triangle")
    }
  }

  // MARK: Links

  /// `brb://pair?c=<code>&h=<host>` pairs; `brb://mac/<id>` (from a widget) opens that Mac, or its alarm.
  func open(url: URL) {
    if let code = PairingCode.parse(url.absoluteString) {
      onboarding = Onboarding(step: .scan, extra: Prefs.onboarded || !macs.isEmpty)
      Task { await claim(code) }
      return
    }
    guard url.scheme == "brb", url.host == "mac" else { return }
    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let q = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).compactMap { i in i.value.map { (i.name, $0) } })
    let id = q["id"] ?? url.lastPathComponent
    route(toMac: id, alarm: q["alarm"] == "1")
  }

  // MARK: Launch arguments (demo, screenshots)

  func applyLaunchDestination() {
    guard let open = launch.open else { return }
    let first = macs.first
    let alarmMac = macs.first { $0.look.isAlarm } ?? first
    switch open {
    case "mac":
      if let m = focusMac { devicesPath = [.mac(m.id)] }
    case "alarm":
      if let m = alarmMac { alarmMacID = m.id }
    case "records":
      tab = .records
    case "record", "evidence", "share":
      guard let m = first else { return }
      Task {
        await loadAllHistory()
        let pick = m.sessions.first { $0.kind == .alarm } ?? m.sessions.first
        switch open {
        case "record":
          tab = .records
          if let pick { recordsPath = [.record(mac: m.id, id: pick.id)] }
        case "evidence":
          sheet = .evidence(mac: m.id, record: pick?.id)
        default:
          sheet = .share(mac: "", record: nil)
        }
      }
    case "settings": tab = .settings
    case "privacy":
      tab = .settings
      settingsPath = [.privacy]
    case "faq":
      tab = .settings
      settingsPath = [.faq]
    case "start":
      if let m = macs.first(where: { $0.look == .idle }) ?? first { sheet = .start(m.id) }
    case "paywall": sheet = .paywall
    case "sendlink": sheet = .sendLink
    default: break
    }
  }

  // MARK: Pairing

  func claim(_ code: PairingCode) async {
    onboarding?.phase = .pairing
    do {
      let claimed = try await backend.claim(code, device: UIDevice.current.name)
      let model = pair(claimed)
      onboarding?.pairedID = model.id
      onboarding?.codeError = false
      onboarding?.phase = .scanning
      onboarding?.step = .paired
    } catch {
      onboarding?.phase = .scanning
      let status = (error as? RelayError)?.status
      let rejected = status == 404 || status == 410
      if case .digits = code, rejected {
        onboarding?.codeError = true
        onboarding?.code = ""
        return
      }
      onboarding?.step = rejected ? .expired : .macoffline
    }
  }

  func rescan() {
    onboarding?.step = .scan
    onboarding?.phase = .scanning
    onboarding?.code = ""
    onboarding?.codeError = false
  }

  func finishOnboarding() {
    Prefs.onboarded = true
    let o = onboarding
    onboarding = nil
    if let o, o.extra, let id = o.pairedID, let m = mac(id) { openMac(m) }
  }

  // MARK: First-run permissions

  func onboardingNext() {
    guard var o = onboarding else { return }
    if o.page < 2 {
      o.page += 1
      onboarding = o
    } else if o.replay {
      finishOnboarding()
    } else {
      o.step = notif == .allowed ? afterNotifications : .notif
      onboarding = o
    }
  }

  private var afterNotifications: Onboarding.Step { Capabilities.criticalAlerts || isDemo ? .crit : .scan }

  func allowNotifications() async {
    if notif == .denied {
      openAppSettings()
      return
    }
    _ = await pushRegistrar.requestAuthorization(critical: false)
    onboarding?.step = afterNotifications
  }

  func skipNotifications() { onboarding?.step = afterNotifications }

  func allowCritical() async {
    setCritical(true)
    _ = await pushRegistrar.requestAuthorization(critical: true)
    onboarding?.step = .scan
  }

  func skipCritical() {
    setCritical(false)
    onboarding?.step = .scan
  }

  // MARK: Demo

  /// For App Review and for trying the app with no Mac: two pretend Macs that play a real alarm.
  func enterDemo() {
    for m in macs { backend.detach(m) }
    let demo = DemoBackend(scene: .idle)
    backend = demo
    macs = demo.paired.map { MacModel(paired: $0) }
    for m in macs { backend.attach(m) }
    Prefs.onboarded = true
    onboarding = nil
    tab = .devices
    devicesPath = []
    notif = .allowed
  }

  func leaveDemo() {
    for m in macs { backend.detach(m) }
    backend = RemoteBackend()
    macs = Library.macs().map { MacModel(paired: $0) }
    for m in macs { backend.attach(m) }
    devicesPath = []
    alarmMacID = nil
    refreshNotificationStatus()
    if macs.isEmpty { onboarding = Onboarding(step: .welcome) }
  }

  // MARK: Test alert

  func sendTestPush() {
    guard let id = onboarding?.pairedID, let m = mac(id) else { return }
    onboarding?.testState = .sending
    Task {
      do {
        try await backend.testPush(for: m)
      } catch {
        onboarding?.testState = .idle
        show(failureText("net"), "exclamationmark.triangle")
        return
      }
      if isDemo {
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        onboarding?.testState = .got
        return
      }
      try? await Task.sleep(nanoseconds: 12_000_000_000)
      if onboarding?.testState == .sending { onboarding?.testState = .idle }
    }
  }

  /// A notification showed up while the app was open; if it is the test one, the row turns green.
  func pushArrived(for id: String) {
    if onboarding?.pairedID == id, onboarding?.testState == .sending { onboarding?.testState = .got }
  }

  /// Settings: "Send a test notification".
  func sendSettingsTestPush() {
    guard let m = focusMac else {
      show(t("noMacs"), "laptopcomputer")
      return
    }
    Task {
      do {
        try await backend.testPush(for: m)
        show(t("testS"), "bell")
      } catch {
        show(failureText("net"), "exclamationmark.triangle")
      }
    }
  }
}
