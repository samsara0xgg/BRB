import Foundation

/// Places the app sends people to. The first is real; the rest are placeholders to fill in before the App Store build.
enum AppLinks {
  static let macDownload = URL(string: "https://github.com/samsara0xgg/BRB/releases/latest/download/BRB.dmg")!

  /// TODO before shipping: the support address, the privacy policy and terms pages, and the App Store id.
  static let support = URL(string: "mailto:support@brb.invalid?subject=BRB")!
  static let privacyPolicy = URL(string: "https://brb.invalid/privacy")!
  static let terms = URL(string: "https://brb.invalid/terms")!
  static let appStoreID = ""

  static var review: URL? {
    appStoreID.isEmpty ? nil : URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")
  }
}
