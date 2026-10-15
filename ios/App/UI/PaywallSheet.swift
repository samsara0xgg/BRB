import SwiftUI
import UIKit

/// BRB Pro: one purchase, bought once, for the Mac and the iPhone. All protection stays free.
struct PaywallSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  private enum Cell {
    case yes, no, text(String)
  }

  private struct Feature {
    var key: String
    var free: Cell
    var pro: Cell
    var note: String?
    var soon = false
  }

  private var features: [Feature] {
    [
      Feature(key: "c0", free: .yes, pro: .yes),
      Feature(key: "c2", free: .yes, pro: .yes),
      Feature(key: "c5", free: .yes, pro: .yes),
      Feature(key: "c3", free: .yes, pro: .yes),
      Feature(key: "c6", free: .no, pro: .yes, note: t("c6s"), soon: true),
      Feature(key: "c7", free: .text(t("c7f")), pro: .text(t("c7c"))),
      Feature(key: "c9", free: .no, pro: .yes),
    ]
  }

  private var price: String { store.entitlements.price ?? t("proPrice") }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        HStack {
          RoundIconButton(symbol: "xmark", label: t("cancel")) { dismiss() }
          Spacer()
        }
        VStack(spacing: 6) {
          Image(systemName: "star.fill")
            .font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 68, height: 68)
            .background(
              LinearGradient(colors: [Color(hex: 0x6f8cff), Color(hex: 0x3a5bd9)], startPoint: .top, endPoint: .bottom),
              in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Theme.tint.opacity(0.35), radius: 14, y: 8)
          Text(t("pwT")).font(.system(size: 26, weight: .bold)).padding(.top, 8)
          Text(t("pwP")).font(.system(size: 15)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
        }
        .padding(.top, 2)
        .padding(.bottom, 18)

        table
        offer.padding(.top, 14)
        cta.padding(.top, 14)
        links.padding(.top, 12)
      }
      .padding(.horizontal, 20)
      .padding(.top, 16)
      .padding(.bottom, 20)
    }
  }

  // MARK: Free and Pro side by side

  private var table: some View {
    VStack(spacing: 0) {
      HStack {
        Text(t("cmpF")).frame(maxWidth: .infinity, alignment: .leading)
        Text(t("cmpFree")).frame(width: 70)
        Text("Pro").foregroundStyle(Theme.tint).frame(width: 70)
      }
      .font(.system(size: 12.5, weight: .semibold))
      .foregroundStyle(Theme.ink2)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      ForEach(features, id: \.key) { f in
        Hairline(inset: 14)
        HStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 2) {
            Text(t(f.key)).font(.system(size: 14.5, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            if f.soon {
              Text(t("soonTag")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.tint)
                .padding(.horizontal, 6).padding(.vertical, 1).background(Theme.tintBg, in: Capsule())
            } else if let note = f.note {
              Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.ink3)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          cell(f.free, pro: false).frame(width: 70)
          cell(f.pro, pro: true).frame(width: 70)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
      }
    }
    .brbCard(radius: 20)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  @ViewBuilder private func cell(_ c: Cell, pro: Bool) -> some View {
    switch c {
    case .yes:
      Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(pro ? Theme.tint : Theme.ink2)
    case .no:
      Text("—").foregroundStyle(Theme.ink3)
    case .text(let s):
      Text(s).font(.system(size: 13, weight: pro ? .semibold : .regular)).foregroundStyle(pro ? Theme.tint : Theme.ink2)
        .multilineTextAlignment(.center)
    }
  }

  // MARK: Price

  private var offer: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(t("ppName")).font(.system(size: 17, weight: .bold))
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(price).font(.rounded(26, .bold))
            if !store.pro {
              Text(t("proPrice0")).font(.system(size: 14)).foregroundStyle(Theme.ink3).strikethrough()
            }
          }
        }
        Spacer()
        if !store.pro {
          Text(t("launchTag")).font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4).background(Theme.tint, in: Capsule())
        }
      }
      VStack(alignment: .leading, spacing: 6) {
        BulletLine(text: t("ppA"))
        BulletLine(text: t("ppB"))
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.tintBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.tint.opacity(0.6), lineWidth: 1.5))
  }

  private var cta: some View {
    VStack(spacing: 8) {
      if store.pro {
        Button {} label: {
          HStack(spacing: 8) {
            Image(systemName: "checkmark")
            Text(t("youHave"))
          }
        }
        .buttonStyle(.big(.glass))
        .disabled(true)
      } else {
        Button { buy() } label: {
          if store.entitlements.busy { ProgressView().tint(.white) } else { Text(t("buyBtn", price)) }
        }
        .buttonStyle(.big(.tint))
        .disabled(store.entitlements.busy)
        Text(t("buyFine", t("proPrice0"))).font(.system(size: 12)).foregroundStyle(Theme.ink3).multilineTextAlignment(.center)
      }
    }
  }

  private var links: some View {
    HStack(spacing: 6) {
      Button(t("restore")) { restore() }
      Text("·")
      Button(t("pp")) { UIApplication.shared.open(AppLinks.privacyPolicy) }
      Text("·")
      Button(t("tos")) { UIApplication.shared.open(AppLinks.terms) }
    }
    .font(.system(size: 12.5))
    .foregroundStyle(Theme.ink3)
    .buttonStyle(.plain)
  }

  private func buy() {
    if store.isDemo {
      store.entitlements.unlockForDemo()
      store.show(t("subscribed"), "star.fill")
      dismiss()
      return
    }
    Task {
      if await store.entitlements.purchase() {
        store.show(t("subscribed"), "star.fill")
        dismiss()
      } else if store.entitlements.product == nil {
        store.show(t("err_store"), "exclamationmark.triangle")
      }
    }
  }

  private func restore() {
    Task {
      let found = await store.entitlements.restore()
      store.show(found ? t("subscribed") : t("restored"), found ? "star.fill" : "info.circle")
      if found { dismiss() }
    }
  }
}

struct BulletLine: View {
  var text: String
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.tint)
      Text(text).font(.system(size: 14))
    }
  }
}
