import Foundation

enum RelayError: Error, Equatable {
  /// The relay answered with this status and `error` text.
  case http(Int, String?)
  /// No answer: offline, timeout, or a host that doesn't exist.
  case network
  case badResponse

  var status: Int? { if case .http(let s, _) = self { return s }; return nil }
  var why: String {
    switch self {
    case .http(_, let e): return e ?? "http"
    case .network: return "net"
    case .badResponse: return "bad"
    }
  }
}

/// A device registered for push, as `POST /device/<id>` takes it.
struct DeviceRegistration: Sendable, Equatable {
  var dev: String
  var name: String
  var apns: String?
  var sandbox: Bool
  var crit: Bool
  var pro: Bool
  var events: [String: Bool]
  var la: String?
  var laStart: String?

  func json() -> [String: Any] {
    var j: [String: Any] = [
      "dev": dev, "name": name, "env": sandbox ? "sandbox" : "production", "lang": isZh ? "zh" : "en",
      "crit": crit, "pro": pro, "events": events,
    ]
    if let apns { j["apns"] = apns }
    if let la { j["la"] = la } else { j["la"] = NSNull() }
    if let laStart { j["laStart"] = laStart } else { j["laStart"] = NSNull() }
    return j
  }
}

/// The relay's HTTP routes, from the phone's side. Everything the app, the widgets and the Watch ask for.
struct RelayAPI: Sendable {
  var host: String
  var id: String
  var token: String
  var session: URLSession = .shared

  init(host: String, id: String, token: String, session: URLSession = .shared) {
    self.host = host; self.id = id; self.token = token; self.session = session
  }

  init(_ mac: PairedMac) { self.init(host: mac.host, id: mac.id, token: mac.token) }

  func url(_ path: String, scheme: String = "https", query: [String: String] = [:]) -> URL {
    var c = URLComponents()
    c.scheme = scheme
    c.host = host
    c.path = path
    var q = query
    if q["t"] == nil { q["t"] = token }
    c.queryItems = q.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    return c.url!
  }

  var watchURL: URL { url("/watch/\(id)", scheme: "wss") }

  // MARK: plumbing

  func request(
    _ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil, timeout: TimeInterval = 15
  ) async throws -> (Data, Int) {
    var req = URLRequest(url: url(path, query: query), timeoutInterval: timeout)
    req.httpMethod = method
    req.cachePolicy = .reloadIgnoringLocalCacheData
    if let body {
      req.httpBody = try? JSONSerialization.data(withJSONObject: body)
      req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    do {
      let (data, resp) = try await session.data(for: req)
      guard let http = resp as? HTTPURLResponse else { throw RelayError.badResponse }
      return (data, http.statusCode)
    } catch let e as RelayError {
      throw e
    } catch {
      throw RelayError.network
    }
  }

  private func check(_ data: Data, _ status: Int) throws {
    guard (200..<300).contains(status) else {
      let err = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
      throw RelayError.http(status, err)
    }
  }

  // MARK: state and history

  /// The same thing a viewer socket sends first. For widgets, the Watch and background refreshes.
  func view() async throws -> RelayView {
    let (data, status) = try await request("GET", "/state/\(id)", timeout: 10)
    try check(data, status)
    guard let v = RelayView(data: data) else { throw RelayError.badResponse }
    return v
  }

  func history() async throws -> [SessionRecord] {
    let (data, status) = try await request("GET", "/h/\(id)")
    try check(data, status)
    guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let arr = j["sessions"] as? [Any]
    else { throw RelayError.badResponse }
    return arr.compactMap {
      guard let d = try? JSONSerialization.data(withJSONObject: $0) else { return nil }
      return try? JSONDecoder().decode(SessionRecord.self, from: d)
    }
  }

  func deleteSession(_ sid: String) async throws {
    let (data, status) = try await request("DELETE", "/h/\(id)/\(sid)")
    try check(data, status)
  }

  /// "Delete my photos and videos in the cloud": the list of sessions stays.
  func deleteAllMedia() async throws {
    let (data, status) = try await request("DELETE", "/h/\(id)")
    try check(data, status)
  }

  func photoURL(_ ms: Ms, pass: String? = nil) -> URL { url("/p/\(id)/\(ms)", query: ["t": pass ?? token]) }

  func photo(_ ms: Ms, pass: String? = nil) async throws -> Data {
    var req = URLRequest(url: photoURL(ms, pass: pass), timeoutInterval: 20)
    req.cachePolicy = .returnCacheDataElseLoad
    do {
      let (data, resp) = try await session.data(for: req)
      guard let http = resp as? HTTPURLResponse else { throw RelayError.badResponse }
      try check(data, http.statusCode)
      return data
    } catch let e as RelayError {
      throw e
    } catch {
      throw RelayError.network
    }
  }

  // MARK: commands

  /// Sends a command over HTTP. `true` means the Mac was online and got it, `false` that the relay queued it.
  func send(_ command: Command, id cid: String) async throws -> Bool {
    let (data, status) = try await request("POST", "/cmd/\(id)", body: command.body(id: cid))
    try check(data, status)
    let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    return (j?["delivered"] as? NSNumber)?.boolValue ?? false
  }

  // MARK: devices and push

  func register(_ reg: DeviceRegistration) async throws {
    let (data, status) = try await request("POST", "/device/\(id)", body: reg.json())
    try check(data, status)
  }

  func unregister(dev: String) async throws {
    let (data, status) = try await request("DELETE", "/device/\(id)/\(dev)")
    try check(data, status)
  }

  func testPush() async throws {
    let (data, status) = try await request("POST", "/test-push/\(id)")
    try check(data, status)
  }

  // MARK: pairing

  /// Trades a pairing code (or the QR's string) for the owner token. Needs no token of its own.
  static func claim(host: String, code: String, device: String, session: URLSession = .shared) async throws -> Claimed {
    guard let url = URL(string: "https://\(host)/claim") else { throw RelayError.network }
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code, "device": device])
    let data: Data, status: Int
    do {
      let (d, resp) = try await session.data(for: req)
      data = d
      status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    } catch {
      throw RelayError.network
    }
    guard (200..<300).contains(status) else {
      let err = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
      throw RelayError.http(status, err)
    }
    guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let id = j["id"] as? String, let token = j["token"] as? String
    else { throw RelayError.badResponse }
    return Claimed(
      id: id, token: token, name: j["name"] as? String ?? "", model: j["model"] as? String ?? "",
      host: j["host"] as? String ?? host)
  }
}

/// What a scanned QR code or a typed code means.
enum PairingCode {
  case qr(host: String, code: String)
  case digits(String)

  /// `https://<host>/pair/<qr>`, `brb://pair?c=<qr>&h=<host>`, or six digits.
  static func parse(_ text: String) -> PairingCode? {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let digits = s.filter { $0.isNumber }
    if s.range(of: #"^[0-9 ]{6,7}$"#, options: .regularExpression) != nil, digits.count == 6 { return .digits(digits) }
    guard let u = URLComponents(string: s) else { return nil }
    if u.scheme == "brb" {
      let q = Dictionary(uniqueKeysWithValues: (u.queryItems ?? []).compactMap { i in i.value.map { (i.name, $0) } })
      guard let c = q["c"], validQR(c) else { return nil }
      return .qr(host: q["h"] ?? RelayDefaults.host, code: c)
    }
    if (u.scheme == "https" || u.scheme == "http"), let host = u.host, u.path.hasPrefix("/pair/") {
      let c = String(u.path.dropFirst("/pair/".count))
      return validQR(c) ? .qr(host: host, code: c) : nil
    }
    return nil
  }

  private static func validQR(_ c: String) -> Bool { c.range(of: #"^[a-z0-9]{8,32}$"#, options: .regularExpression) != nil }
}
