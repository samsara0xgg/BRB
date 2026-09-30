import AppKit

/// Phone push through ntfy (https://ntfy.sh): the phone's ntfy app subscribes to a random topic
/// name, which is the only secret. Off until turned on in the panel. ntfy.sh keeps an attached
/// photo for 3 hours.
enum Push {
  static var enabled: Bool {
    get { UserDefaults.standard.bool(forKey: "pushEnabled") }
    set { UserDefaults.standard.set(newValue, forKey: "pushEnabled") }
  }

  /// Created on first use and kept, so turning push off and on again needs no new subscription.
  static var topic: String {
    if let t = UserDefaults.standard.string(forKey: "ntfyTopic") { return t }
    let t = "guardmode-" + Live.random(20)
    UserDefaults.standard.set(t, forKey: "ntfyTopic")
    return t
  }

  /// Scanned from the panel: ntfy's app opens it as a subscription.
  static var subscribeURL: URL { URL(string: "https://ntfy.sh/" + topic)! }

  /// The alarm itself: what happened, whether the siren is on, and the first photo.
  static func alarm(_ trigger: Trigger, at date: Date, test: Bool, link: URL, photo: Data?) {
    let time = Clock.time.string(from: date)
    let body = trigger.sirenAtOnce ? L("%@ · Siren on", time) : L("%@ · Screen locked, siren in 10 s", time)
    send(title: titled(trigger.headline, test), message: body, priority: 5, link: link, photo: photo)
  }

  /// The soft stage ran out and nobody disarmed it.
  static func siren(test: Bool, link: URL, photo: Data?) {
    send(title: titled(L("The siren is sounding"), test), message: L("It's been 10 s and nobody has disarmed it"), priority: 5, link: link, photo: photo)
  }

  static func disarmed(_ how: Disarm, at date: Date, test: Bool) {
    send(title: titled(L("Disarmed"), test), message: L("%@ · %@", Clock.time.string(from: date), how.phrase), priority: 2, link: nil, photo: nil)
  }

  /// Something stopped working while armed, and the Mac is only partly guarded.
  static func warning(_ message: String, test: Bool) {
    send(title: titled(L("Guard Mode needs a look"), test), message: message, priority: 4, link: nil, photo: nil)
  }

  private static func titled(_ title: String, _ test: Bool) -> String { test ? L("Test: %@", title) : title }

  /// Sends one notification, retrying every 5 s up to 5 times (the Mac may be between networks).
  /// Priority 5 is ntfy's "urgent", which its iPhone app turns into a critical alert.
  static func send(title: String, message: String, priority: Int, link: URL?, photo: Data?, attempt: Int = 1, done: ((Bool) -> Void)? = nil) {
    var url = URLComponents(string: "https://ntfy.sh/" + topic)!
    url.queryItems = [.init(name: "title", value: title), .init(name: "message", value: message), .init(name: "priority", value: String(priority))]
    if priority >= 5 { url.queryItems!.append(.init(name: "tags", value: "rotating_light")) }
    if let link {  // tapping the notification, or its button, opens the phone page
      url.queryItems! += [.init(name: "click", value: link.absoluteString),
                          .init(name: "actions", value: "view, \(L("Watch live")), \(link.absoluteString)")]
    }
    if photo != nil { url.queryItems!.append(.init(name: "filename", value: "guardmode.jpg")) }
    // `+` is left alone in a query and read as a space by some servers.
    url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    var request = URLRequest(url: url.url!, timeoutInterval: 15)
    request.httpMethod = "PUT"
    request.httpBody = photo
    URLSession.shared.dataTask(with: request) { _, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      DispatchQueue.main.async {
        if status == 200 {
          log("push sent: \(title)" + (photo.map { " with a \($0.count / 1024) KB photo" } ?? ""))
          done?(true)
          return
        }
        log("push failed (attempt \(attempt)): \(error?.localizedDescription ?? "HTTP \(status)")")
        guard attempt < 5 else { done?(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
          send(title: title, message: message, priority: priority, link: link, photo: photo, attempt: attempt + 1, done: done)
        }
      }
    }.resume()
  }

  /// A test notification with a photo from the camera, for checking the phone's subscription.
  static func test(done: ((Bool) -> Void)? = nil) {
    let camera = Recorder()
    do { try camera.start() } catch { log("test push without a photo: \(error)") }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {  // let the exposure settle
      camera.photo { photo in
        camera.stop()
        send(title: L("Guard Mode test"), message: L("If you see this, alarms will reach this phone."), priority: 3, link: nil, photo: photo, done: done)  // no link: ntfy keeps it, and the owner link must not leak
      }
    }
  }
}
