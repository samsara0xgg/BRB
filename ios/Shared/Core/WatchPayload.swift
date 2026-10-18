import Foundation

/// What the iPhone tells the Watch over WatchConnectivity (`updateApplicationContext`): which Macs are
/// paired and whether Pro is unlocked. The Watch talks to the relay itself with these tokens.
struct WatchPayload: Equatable, Sendable {
  var macs: [PairedMac]
  var pro: Bool

  static let macsKey = "macs"
  static let proKey = "pro"

  var context: [String: Any] {
    [WatchPayload.macsKey: (try? JSONEncoder().encode(macs)) ?? Data(), WatchPayload.proKey: pro]
  }

  init(macs: [PairedMac], pro: Bool) {
    self.macs = macs
    self.pro = pro
  }

  init?(context: [String: Any]) {
    guard let data = context[WatchPayload.macsKey] as? Data, let macs = try? JSONDecoder().decode([PairedMac].self, from: data)
    else { return nil }
    self.macs = macs
    self.pro = context[WatchPayload.proKey] as? Bool ?? false
  }
}
