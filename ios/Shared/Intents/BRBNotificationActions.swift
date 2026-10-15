import Foundation
import UserNotifications

/// The buttons on a long-pressed alarm notification: "Stop siren" and "Open". The relay's alarm pushes carry
/// the category `BRB_ALARM`. The app registers these once at launch and hands each tapped action to `handle`.
enum BRBNotificationActions {
  static let alarmCategory = "BRB_ALARM"
  /// For the local "You left the café Wi‑Fi and your Mac isn't guarded" reminder; put the room id in its userInfo as "id".
  static let remindCategory = "BRB_REMIND"

  static let hushID = "BRB_HUSH"
  static let startID = "BRB_START"
  static let openID = "BRB_OPEN"

  /// `UNUserNotificationCenter.current().setNotificationCategories(BRBNotificationActions.categories())`
  static func categories() -> Set<UNNotificationCategory> {
    let hushAction = UNNotificationAction(identifier: hushID, title: t("ab_stop"), options: [])
    let startAction = UNNotificationAction(identifier: startID, title: t("btn_start"), options: [])
    let openAction = UNNotificationAction(identifier: openID, title: t("open"), options: [.foreground])
    let alarm = UNNotificationCategory(
      identifier: alarmCategory, actions: [hushAction, openAction], intentIdentifiers: [], options: [])
    let remind = UNNotificationCategory(
      identifier: remindCategory, actions: [startAction, openAction], intentIdentifiers: [], options: [])
    return [alarm, remind]
  }

  /// Runs a tapped action. True when it was one of ours (the app handles `UNNotificationDefaultActionIdentifier`
  /// and `BRB_OPEN` itself by opening the right page).
  static func handle(actionIdentifier: String, userInfo: [AnyHashable: Any]) async -> Bool {
    let id = userInfo["id"] as? String
    switch actionIdentifier {
    case hushID:
      _ = await BRBCommander.hushSiren(macID: id)
      return true
    case startID:
      _ = await BRBCommander.startGuarding(macID: id, place: nil)
      return true
    default:
      return false
    }
  }
}
