import UIKit
import UserNotifications

/// Tells the relay where to send this phone's alerts: one registration per paired Mac.
@MainActor
final class PushRegistrar {
  unowned let store: AppStore
  init(store: AppStore) { self.store = store }

  func registration(for mac: MacModel) -> DeviceRegistration {
    #if DEBUG
      let sandbox = true
    #else
      let sandbox = false
    #endif
    return DeviceRegistration(
      dev: Prefs.deviceID, name: UIDevice.current.name, apns: store.pushToken, sandbox: sandbox,
      crit: store.criticalAlerts && Capabilities.criticalAlerts,
      pro: store.pro, events: store.eventPrefs, la: store.liveActivityTokens[mac.id], laStart: store.pushToStartToken)
  }

  func registerAll() {
    guard !store.isDemo else { return }
    for mac in store.macs { register(mac) }
  }

  func register(_ mac: MacModel) {
    guard !store.isDemo else { return }
    let reg = registration(for: mac)
    Task { await store.backend.register(reg, for: mac) }
  }

  /// The alert permission prompt. Critical alerts are asked for with it; iOS only shows that part when the
  /// app has Apple's critical-alerts entitlement.
  func requestAuthorization(critical: Bool) async -> Bool {
    var options: UNAuthorizationOptions = [.alert, .sound, .badge]
    if critical && Capabilities.criticalAlerts { options.insert(.criticalAlert) }
    let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    if granted { UIApplication.shared.registerForRemoteNotifications() }
    store.refreshNotificationStatus()
    return granted
  }
}

enum NotificationIDs {
  static let alarmCategory = "BRB_ALARM"
  static let guardCategory = "BRB_GUARD"
  static let hush = "hush"
  static let open = "open"
  static let stopGuard = "stopGuard"
  static let startGuard = "startGuard"
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(
    _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    let hush = UNNotificationAction(identifier: NotificationIDs.hush, title: t("lp_stop"), options: [])
    let open = UNNotificationAction(identifier: NotificationIDs.open, title: t("lp_open"), options: [.foreground])
    let stop = UNNotificationAction(identifier: NotificationIDs.stopGuard, title: t("lp_stopGuard"), options: [.authenticationRequired])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: NotificationIDs.alarmCategory, actions: [hush, open], intentIdentifiers: [], options: []),
      UNNotificationCategory(identifier: NotificationIDs.guardCategory, actions: [stop], intentIdentifiers: [], options: []),
    ])
    WatchBridge.shared.start()
    if !AppStore.shared.isDemo { application.registerForRemoteNotifications() }
    return true
  }

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    Task { @MainActor in
      AppStore.shared.pushToken = hex
      AppStore.shared.pushRegistrar.registerAll()
    }
  }

  /// A silent push (content-available): refresh the Macs so the widgets and the Watch are up to date.
  func application(
    _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    Task { @MainActor in
      let store = AppStore.shared
      for m in store.macs { await store.backend.refresh(m) }
      completionHandler(.newData)
    }
  }

  // Foreground: alarms show as a banner unless that Mac's alarm page is already open.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let id = notification.request.content.userInfo["id"] as? String
    Task { @MainActor in
      let store = AppStore.shared
      if let id { store.pushArrived(for: id) }
      if let id, store.alarmMacID == id { completionHandler([]) } else { completionHandler([.banner, .sound, .list]) }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    let id = info["id"] as? String
    let action = response.actionIdentifier
    Task { @MainActor in
      let store = AppStore.shared
      guard let id, let mac = store.mac(id) else { completionHandler(); return }
      switch action {
      case NotificationIDs.hush:
        await store.hush(mac)
      case NotificationIDs.stopGuard:
        await store.send(.stop, to: mac)
      default:
        store.route(toMac: id, alarm: response.notification.request.content.categoryIdentifier == NotificationIDs.alarmCategory)
      }
      completionHandler()
    }
  }
}
