import Observation
import StoreKit

/// BRB Pro: one non-consumable purchase, bought once for the Mac and the iPhone.
@Observable @MainActor
final class Entitlements {
  static let productID = "com.allen.brb.pro"

  /// 1.0 sells nothing: no plan card, paywall or restore, no Apple Watch app (project.yml builds it but
  /// doesn't embed it), and every phone tells the relay it has no Pro, so photos stay 7 days. Turn this on
  /// with the in-app purchase in App Store Connect and the Watch app's `embed`.
  static let onSale = false

  var pro = Prefs.pro
  var product: Product?
  var busy = false
  var onChange: (() -> Void)?
  private var updates: Task<Void, Never>?
  private var forced = false

  func start(forcePro: Bool) {
    if forcePro {
      forced = true
      pro = true
      return
    }
    guard Entitlements.onSale else { set(false); return }
    updates = Task { [weak self] in
      for await result in Transaction.updates {
        guard let self else { return }
        await self.handle(result)
      }
    }
    Task { await refresh() }
  }

  /// The price to show, from the App Store, or nil until it arrives.
  var price: String? { product?.displayPrice }

  func refresh() async {
    guard !forced else { return }
    if product == nil {
      product = try? await Product.products(for: [Entitlements.productID]).first
    }
    var owned = false
    for await result in Transaction.currentEntitlements {
      if case .verified(let tx) = result, tx.productID == Entitlements.productID, tx.revocationDate == nil { owned = true }
    }
    set(owned)
  }

  private func handle(_ result: VerificationResult<Transaction>) async {
    if case .verified(let tx) = result {
      if tx.productID == Entitlements.productID { set(tx.revocationDate == nil) }
      await tx.finish()
    }
  }

  private func set(_ value: Bool) {
    guard pro != value else { return }
    pro = value
    Prefs.pro = value
    onChange?()
  }

  /// The demo has no App Store behind it: "buying" just turns Pro on until the app closes.
  func unlockForDemo() { pro = true }

  /// Buys it. Returns true when the purchase went through.
  func purchase() async -> Bool {
    guard let product else { return false }
    busy = true
    defer { busy = false }
    guard let result = try? await product.purchase() else { return false }
    switch result {
    case .success(let verification):
      if case .verified(let tx) = verification {
        set(true)
        await tx.finish()
        return true
      }
      return false
    default: return false
    }
  }

  /// "Restore purchases". True when something was found.
  func restore() async -> Bool {
    busy = true
    defer { busy = false }
    try? await StoreKit.AppStore.sync()
    await refresh()
    return pro
  }
}
