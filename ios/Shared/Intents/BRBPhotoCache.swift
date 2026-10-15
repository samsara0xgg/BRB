import Foundation

/// Alarm photos kept in the app group, so the Live Activity can show the newest one. A Live Activity can't
/// download anything while it draws, so whoever has the photo first (the notification extension, or the app
/// when a state arrives) puts it here, and the activity reads it from here. The file is
/// `photos/<room id>-<ms>.jpg`; the notification extension writes the same names.
enum BRBPhotoCache {
  static var directory: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.group)?
      .appendingPathComponent("photos", isDirectory: true)
  }

  static func fileURL(macID: String, ms: Ms) -> URL? {
    directory?.appendingPathComponent("\(macID)-\(ms).jpg")
  }

  static func contains(macID: String, ms: Ms) -> Bool {
    guard let url = fileURL(macID: macID, ms: ms) else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  static func store(_ data: Data, macID: String, ms: Ms) {
    guard let dir = directory, let url = fileURL(macID: macID, ms: ms) else { return }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? data.write(to: url, options: .atomic)
    prune()
  }

  /// Downloads one photo with the alarm's viewing token (`pass`) or, without it, the owner token, and keeps it.
  /// True when the photo is in the cache afterwards.
  @discardableResult
  static func fetch(macID: String, ms: Ms, pass: String?) async -> Bool {
    if contains(macID: macID, ms: ms) { return true }
    guard ms > 0, let mac = Library.macs().first(where: { $0.id == macID }) else { return false }
    let relay = BRBLoader.api(for: mac, timeout: 10)
    guard let data = try? await relay.photo(ms, pass: pass), !data.isEmpty else { return false }
    store(data, macID: macID, ms: ms)
    return contains(macID: macID, ms: ms)
  }

  /// Keeps the 12 newest files and nothing older than two days.
  static func prune() {
    guard let dir = directory else { return }
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
    let dated: [(URL, Date)] = urls.map { url in
      let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? Date.distantPast
      return (url, date)
    }
    let newestFirst = dated.sorted { $0.1 > $1.1 }
    let cutoff = Date().addingTimeInterval(-2 * 86_400)
    for (index, item) in newestFirst.enumerated() where index >= 12 || item.1 < cutoff {
      try? FileManager.default.removeItem(at: item.0)
    }
  }
}
