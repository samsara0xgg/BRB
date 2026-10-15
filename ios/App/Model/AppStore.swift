import LocalAuthentication
import Observation
import SwiftUI
import UserNotifications

enum Tab: String, Hashable { case devices, records, settings }

enum Route: Hashable {
  case mac(String)
  case record(mac: String, id: String)
  case privacy
  case faq
}

enum Sheet: Identifiable, Equatable {
  case start(String)
  case paywall
  case share(mac: String, record: String?)
  case evidence(mac: String, record: String?)
  case message(String)
  case sendLink

  var id: String {
    switch self {
    case .start(let m): return "start-\(m)"
    case .paywall: return "paywall"
    case .share(let m, let r): return "share-\(m)-\(r ?? "-")"
    case .evidence(let m, let r): return "evidence-\(m)-\(r ?? "-")"
    case .message(let m): return "message-\(m)"
    case .sendLink: return "sendLink"
    }
  }
}

struct ToastSpec: Identifiable, Equatable {
  let id = UUID()
  var text: String
  var symbol: String
}

struct AlertSpec: Identifiable {
  struct Action {
    var label: String
    var role: ButtonRole?
    var run: () -> Void
    init(_ label: String, role: ButtonRole? = nil, run: @escaping () -> Void = {}) {
      self.label = label; self.role = role; self.run = run
    }
  }
  let id = UUID()
  var title: String
  var message: String?
  /// A text field with this starting text.
  var input: String?
  var actions: [Action]
}

enum NotifStatus { case unknown, allowed, denied }

@Observable @MainActor
final class AppStore {
  static let shared = AppStore()

  var backend: Backend
  var macs: [MacModel] = []
  var tab: Tab = .devices
  var devicesPath: [Route] = []
  var recordsPath: [Route] = []
  var settingsPath: [Route] = []

  var sheet: Sheet?
  var alert: AlertSpec?
  var alertInput = ""
  var toast: ToastSpec?
  var alarmMacID: String?
  var onboarding: Onboarding?

  var faceRequired = Prefs.faceRequired
  var criticalAlerts = Prefs.critical
  var eventPrefs = Prefs.events
  var notif: NotifStatus = .unknown
  var phoneOffline = false
  var recordsBadge = false
  var recordFilterAlarms = false
  var recordMac: String?
  /// An error the whole screen should show instead of cards ("Can't reach BRB").
  var loadFailed = false
  /// The app is in front (so an alarm can open its page by itself).
  var appActive = true

  let entitlements = Entitlements()
  var pro: Bool { entitlements.pro }
  var pushToken: String?
  var liveActivityTokens: [String: String] = [:]
  var pushToStartToken: String?
  let launch = LaunchOptions()
  let network = NetworkMonitor()
  @ObservationIgnored private var toastTask: Task<Void, Never>?

  init() {
    if launch.demo {
      backend = DemoBackend(scene: launch.scene)
    } else {
      backend = RemoteBackend()
    }
  }

  var isDemo: Bool { backend.isDemo }
  var demo: DemoBackend? { backend as? DemoBackend }

  // MARK: Launch

  func bootstrap() {
    guard macs.isEmpty else { return }
    entitlements.onChange = { [weak self] in self?.proChanged() }
    entitlements.start(forcePro: launch.pro)
    if let demo {
      if launch.scene != .empty { macs = demo.paired.map { MacModel(paired: $0) } }
      Prefs.onboarded = true
    } else {
      macs = Library.macs().map { MacModel(paired: $0) }
    }
    if macs.isEmpty && !Prefs.onboarded { onboarding = Onboarding(step: .welcome) }
    if launch.scene == .empty { onboarding = nil }
    for m in macs { backend.attach(m) }
    if let step = launch.onboardingStep { onboarding = Onboarding(step: step) }
    refreshNotificationStatus()
    if !isDemo {
      network.onChange = { [weak self] offline in self?.phoneOffline = offline }
      network.start()
      liveActivities.start()
    }
    applyLaunchDestination()
  }

  func mac(_ id: String?) -> MacModel? { macs.first { $0.id == id } }

  /// The Mac the phone should talk about first: in alarm, arming, guarding, else the first.
  var focusMac: MacModel? {
    macs.first { $0.look.isAlarm } ?? macs.first { $0.look == .arming } ?? macs.first { $0.look.isGuarding } ?? macs.first
  }

  func scenePhase(active: Bool) {
    appActive = active
    guard !isDemo else { return }
    if active {
      for m in macs { backend.attach(m); Task { await backend.refresh(m) } }
      refreshNotificationStatus()
      Task { await entitlements.refresh() }
    }
  }

  // MARK: Pairing

  func pair(_ claimed: Claimed) -> MacModel {
    let record = PairedMac(
      id: claimed.id, token: claimed.token, host: claimed.host, name: claimed.name, model: claimed.model, custom: nil, added: nowMs())
    if let existing = mac(record.id) { return existing }
    let model = MacModel(paired: record, snapshot: MacSnapshot(paired: record))
    macs.append(model)
    if !isDemo { Library.save(macs.map(\.paired)) }
    backend.attach(model)
    pushRegistrar.registerAll()
    return model
  }

  func unpair(_ mac: MacModel) {
    backend.detach(mac)
    Task { await backend.unregister(dev: Prefs.deviceID, for: mac) }
    macs.removeAll { $0.id == mac.id }
    if !isDemo {
      Library.save(macs.map(\.paired))
      Library.forget(id: mac.id)
    }
    if alarmMacID == mac.id { alarmMacID = nil }
    devicesPath.removeAll { if case .mac(let id) = $0 { return id == mac.id }; return false }
    syncWatch()
    show(t("unpaired"), "link.badge.plus")
  }

  func persist() {
    if !isDemo { Library.save(macs.map(\.paired)) }
    syncWatch()
  }

  func rename(_ mac: MacModel, to name: String) {
    mac.rename(name)
    persist()
    show(t("renamed"), "pencil")
  }

  // MARK: Commands

  /// Sends a command, tells the owner when it was queued or refused, and returns what happened.
  @discardableResult
  func send(_ command: Command, to mac: MacModel) async -> CommandResult {
    let result = await backend.send(command, to: mac)
    switch result {
    case .queued: show(t("toastQueued"), "clock")
    case .failed(let why): show(failureText(why), "exclamationmark.triangle")
    case .done: break
    }
    return result
  }

  func failureText(_ why: String) -> String {
    switch why {
    case "not-ready": return t("err_notready")
    case "busy": return t("err_busy")
    case "locked": return t("err_locked")
    case "forbidden": return t("err_forbidden")
    case "net": return t("err_net")
    default: return t("err_failed")
    }
  }

  func startGuarding(_ mac: MacModel, place: Place, note: String) async -> CommandResult {
    Prefs.lastPlace = place
    Prefs.lastNote = note
    let result = await send(.start(place: place, note: note, test: nil), to: mac)
    return result
  }

  func cancelArming(_ mac: MacModel) async {
    if case .done = await send(.stop, to: mac) { show(t("toastCancel"), "xmark") }
  }

  func stopGuarding(_ mac: MacModel) async {
    guard await authenticate(t("lp_stopGuard")) else { return }
    if case .done = await send(.stop, to: mac) { show(t("toastStop"), "shield") }
  }

  func hush(_ mac: MacModel) async { await send(.hush, to: mac) }

  func disarm(_ mac: MacModel) async {
    guard await authenticate(t("ab_dis")) else { return }
    await send(.disarm, to: mac)
  }

  /// Face ID (or the passcode) before something that ends a guard. Skipped when the owner turned it off.
  func authenticate(_ reason: String, always: Bool = false) async -> Bool {
    guard faceRequired || always else { return true }
    if isDemo { return true }
    let context = LAContext()
    var error: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
    do {
      return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    } catch {
      return false
    }
  }

  // MARK: History

  func loadHistory(_ mac: MacModel, force: Bool = false) async {
    if mac.sessionsState == .loading { return }
    if mac.sessionsState == .loaded && !force { return }
    mac.sessionsState = .loading
    do {
      mac.sessions = try await backend.history(of: mac).sorted { $0.end > $1.end }
      mac.sessionsState = .loaded
    } catch {
      mac.sessionsState = mac.sessions.isEmpty ? .failed : .loaded
    }
  }

  func loadAllHistory(force: Bool = false) async {
    for m in macs { await loadHistory(m, force: force) }
  }

  func deleteRecord(_ record: SessionRecord, of mac: MacModel) async {
    do {
      try await backend.deleteSession(record.id, of: mac)
      mac.sessions.removeAll { $0.id == record.id }
      show(t("deleted"), "trash")
    } catch {
      show(failureText("net"), "exclamationmark.triangle")
    }
  }

  func deleteCloudMedia() async {
    var ok = true
    for m in macs {
      do { try await backend.deleteMedia(of: m) } catch { ok = false }
    }
    show(ok ? t("delCloudDone") : failureText("net"), ok ? "trash" : "exclamationmark.triangle")
  }

  // MARK: Surfaces

  func show(_ text: String, _ symbol: String = "checkmark") {
    let spec = ToastSpec(text: text, symbol: symbol)
    toast = spec
    toastTask?.cancel()
    toastTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_300_000_000)
      guard !Task.isCancelled else { return }
      if self?.toast == spec { self?.toast = nil }
    }
  }

  func present(_ alert: AlertSpec) {
    alertInput = alert.input ?? ""
    self.alert = alert
  }

  func openAlarm(_ mac: MacModel) {
    alarmMacID = mac.id
  }

  func closeAlarm() {
    if let m = mac(alarmMacID), m.finished != nil { m.finished = nil }
    alarmMacID = nil
  }

  func openMac(_ mac: MacModel, tab: Tab = .devices) {
    self.tab = tab
    if case .mac(mac.id)? = devicesPath.last { return }
    devicesPath = [.mac(mac.id)]
  }

  /// A push or a link says "look at this Mac".
  func route(toMac id: String, alarm: Bool) {
    guard let m = mac(id) else { return }
    tab = .devices
    if alarm && (m.alarmActive || m.finished != nil) { openAlarm(m) } else { openMac(m) }
    Task { await backend.refresh(m) }
  }

  // MARK: Settings

  func setFaceRequired(_ on: Bool) {
    faceRequired = on
    Prefs.faceRequired = on
  }

  func setCritical(_ on: Bool) {
    criticalAlerts = on
    Prefs.critical = on
    pushRegistrar.registerAll()
  }

  func setEvent(_ key: String, _ on: Bool) {
    eventPrefs[key] = on
    Prefs.events = eventPrefs
    pushRegistrar.registerAll()
  }

  func refreshNotificationStatus() {
    guard !isDemo else {
      notif = launch.notifOff ? .denied : .allowed
      return
    }
    Task {
      let s = await UNUserNotificationCenter.current().notificationSettings()
      switch s.authorizationStatus {
      case .authorized, .provisional, .ephemeral: notif = .allowed
      case .denied: notif = .denied
      default: notif = .unknown
      }
    }
  }

  @ObservationIgnored lazy var pushRegistrar = PushRegistrar(store: self)
  @ObservationIgnored lazy var liveActivities = LiveActivityController(store: self)

  func proChanged() {
    syncWatch()
    pushRegistrar.registerAll()
  }

  func syncWatch() {
    WatchBridge.shared.send(macs: macs.map(\.paired), pro: pro)
  }
}
