import AppKit

/// Phone push through ntfy (https://ntfy.sh): the phone's ntfy app subscribes to a random topic
/// name, which is the only secret. Off until turned on in the menu. ntfy.sh keeps an attached
/// photo for 3 hours.
enum Push {
  static var enabled: Bool {
    get { UserDefaults.standard.bool(forKey: "pushEnabled") }
    set { UserDefaults.standard.set(newValue, forKey: "pushEnabled") }
  }

  /// Created on first use and kept, so turning push off and on again needs no new subscription.
  static var topic: String {
    if let t = UserDefaults.standard.string(forKey: "ntfyTopic") { return t }
    let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
    let t = "guardmode-" + String((0..<20).map { _ in alphabet.randomElement()! })
    UserDefaults.standard.set(t, forKey: "ntfyTopic")
    return t
  }

  /// Sends one notification, retrying every 5 s up to 5 times (the Mac may be between networks).
  /// Priority 5 is ntfy's "urgent", which its iPhone app is to turn into a critical alert.
  static func send(title: String, message: String, priority: Int, photo: Data?, attempt: Int = 1, done: ((Bool) -> Void)? = nil) {
    var url = URLComponents(string: "https://ntfy.sh/" + topic)!
    url.queryItems = [.init(name: "title", value: title), .init(name: "message", value: message), .init(name: "priority", value: String(priority))]
    if priority >= 5 { url.queryItems!.append(.init(name: "tags", value: "rotating_light")) }
    if photo != nil { url.queryItems!.append(.init(name: "filename", value: "guardmode.jpg")) }
    var request = URLRequest(url: url.url!, timeoutInterval: 15)
    request.httpMethod = "PUT"
    request.httpBody = photo
    URLSession.shared.dataTask(with: request) { _, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      DispatchQueue.main.async {
        if status == 200 {
          log("push sent" + (photo.map { " with a \($0.count / 1024) KB photo" } ?? ", no photo"))
          done?(true)
          return
        }
        log("push failed (attempt \(attempt)): \(error?.localizedDescription ?? "HTTP \(status)")")
        guard attempt < 5 else { done?(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
          send(title: title, message: message, priority: priority, photo: photo, attempt: attempt + 1, done: done)
        }
      }
    }.resume()
  }

  /// A test notification with a photo from the camera, for checking the phone's subscription.
  static func test(done: ((Bool) -> Void)? = nil) {
    let camera = Recorder()
    do { try camera.startCamera() } catch { log("test push without a photo: \(error)") }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {  // let the exposure settle
      camera.snapshot { photo in
        camera.stop()
        send(title: "GuardMode 测试推送", message: "收到这条，报警时就会推送到这台手机。", priority: 3, photo: photo, done: done)
      }
    }
  }

  static func copyTopic() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(topic, forType: .string)
  }
}
