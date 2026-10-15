import Foundation
import UserNotifications

/// Puts the alarm photo on the notification. The relay's alarm push carries `id` (the room), `pass` (a viewing
/// token for this alarm), `photo` (the photo's time in ms, or null) and `at`. This downloads
/// `https://<host>/p/<id>/<photo>?t=<pass>`, attaches it, and delivers the notification with or without it.
/// It never fails the push: missing keys, a slow network or an unreadable picture all end in `contentHandler`.
final class NotificationService: UNNotificationServiceExtension {
  private let lock = NSLock()
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var content: UNMutableNotificationContent?
  private var task: URLSessionDownloadTask?
  private var session: URLSession?

  override func didReceive(
    _ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    let mutable = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
    lock.lock()
    self.contentHandler = contentHandler
    self.content = mutable
    lock.unlock()

    let info = request.content.userInfo
    guard let id = NotificationService.text(info["id"]), !id.isEmpty else {
      deliver()
      return
    }
    if mutable.threadIdentifier.isEmpty { mutable.threadIdentifier = id }

    guard let photo = NotificationService.millis(info["photo"]), photo > 0 else {
      deliver()
      return
    }
    // The alarm's viewing token, else the owner token of that Mac if this phone has paired with it.
    let paired = Library.macs().first(where: { $0.id == id })
    guard let token = NotificationService.text(info["pass"]) ?? paired?.token, !token.isEmpty else {
      deliver()
      return
    }
    let api = RelayAPI(host: paired?.host ?? RelayDefaults.host, id: id, token: token)
    let url = api.photoURL(photo, pass: token)

    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 12
    config.timeoutIntervalForResource = 20
    let session = URLSession(configuration: config)
    let task = session.downloadTask(with: url) { [weak self] file, response, error in
      guard let self = self else { return }
      if error == nil, let file = file, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
        self.attach(file, roomID: id, photo: photo)
      }
      self.deliver()
    }
    lock.lock()
    self.session = session
    self.task = task
    lock.unlock()
    task.resume()
  }

  /// About 30 seconds are up: deliver what there is.
  override func serviceExtensionTimeWillExpire() {
    lock.lock()
    let running = task
    lock.unlock()
    running?.cancel()
    deliver()
  }

  // MARK: pieces

  /// Moves the download to a `.jpg` of its own (the system wants a file extension), attaches it, and keeps a
  /// copy in the app group, where the Live Activity looks for it, when this extension may use the group.
  private func attach(_ downloaded: URL, roomID: String, photo: Int64) {
    let fm = FileManager.default
    let dest = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
    do {
      try fm.moveItem(at: downloaded, to: dest)
    } catch {
      return
    }
    if let size = (try? fm.attributesOfItem(atPath: dest.path))?[.size] as? NSNumber, size.intValue == 0 { return }

    if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: Shared.group) {
      let dir = group.appendingPathComponent("photos", isDirectory: true)
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
      let copy = dir.appendingPathComponent("\(roomID)-\(photo).jpg")
      try? fm.removeItem(at: copy)
      try? fm.copyItem(at: dest, to: copy)
    }

    guard let attachment = try? UNNotificationAttachment(
      identifier: "photo", url: dest, options: [UNNotificationAttachmentOptionsTypeHintKey: "public.jpeg"])
    else { return }
    lock.lock()
    content?.attachments = [attachment]
    lock.unlock()
  }

  /// Calls the content handler once, with whatever the content holds by now.
  private func deliver() {
    lock.lock()
    let handler = contentHandler
    let ready = content
    contentHandler = nil
    let running = session
    session = nil
    task = nil
    lock.unlock()
    running?.finishTasksAndInvalidate()
    if let handler = handler, let ready = ready { handler(ready) }
  }

  private static func text(_ value: Any?) -> String? {
    if let s = value as? String { return s }
    return nil
  }

  /// A number the relay sent as a JSON number or a string. `null` and anything else is nil.
  private static func millis(_ value: Any?) -> Int64? {
    if let n = value as? NSNumber { return n.int64Value }
    if let s = value as? String { return Int64(s) }
    return nil
  }
}
