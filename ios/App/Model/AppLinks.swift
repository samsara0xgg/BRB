import Foundation

/// Places the app sends people to. All but the review link are pages on the website, which the relay
/// serves (relay/site.js), so they can change without an app update, in the app's language.
enum AppLinks {
  static let macDownload = URL(string: "https://\(RelayDefaults.site)/mac")!
  static var support: URL { page("support") }
  static var privacyPolicy: URL { page("privacy") }
  static var terms: URL { page("terms") }

  /// The app's Apple ID in App Store Connect, for the review link.
  static let appStoreID = "6824165444"

  static var review: URL? {
    appStoreID.isEmpty ? nil : URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")
  }

  private static func page(_ path: String) -> URL {
    URL(string: "https://\(RelayDefaults.site)/\(path)?lang=\(isZh ? "zh" : "en")")!
  }
}
