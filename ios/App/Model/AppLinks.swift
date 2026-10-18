import Foundation

/// Places the app sends people to. All but the review link are pages on the relay (relay/site.js), so they
/// can change without an app update, in the app's language.
enum AppLinks {
  static let macDownload = URL(string: "https://\(RelayDefaults.host)/mac")!
  static var support: URL { page("support") }
  static var privacyPolicy: URL { page("privacy") }
  static var terms: URL { page("terms") }

  /// TODO once App Store Connect gives it: the app's id, for the review link.
  static let appStoreID = ""

  static var review: URL? {
    appStoreID.isEmpty ? nil : URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")
  }

  private static func page(_ path: String) -> URL {
    URL(string: "https://\(RelayDefaults.host)/\(path)?lang=\(isZh ? "zh" : "en")")!
  }
}
