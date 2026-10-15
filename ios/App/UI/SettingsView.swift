import SwiftUI
import UIKit

struct SettingsView: View {
  @Environment(AppStore.self) private var store

  private var notifOn: Bool { store.notif == .allowed }
  private var version: String {
    let info = Bundle.main.infoDictionary
    let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
    let b = info?["CFBundleVersion"] as? String ?? "1"
    return "\(v) (\(b))"
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        if store.pageState == "offline" { OfflineBar(text: t("setOffline")).padding(.bottom, 10) }
        if store.pageState == "error" {
          ErrorBanner(title: t("setErrT"), message: t("setErrS"), retry: nil).padding(.bottom, 10)
        }
        if store.pageState == "loading" {
          VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
              Skeleton(width: 44, height: 44, radius: 12)
              VStack(alignment: .leading, spacing: 7) {
                Skeleton(width: 120, height: 16)
                Skeleton(width: 200, height: 12)
              }
            }
            Skeleton(height: 40, radius: 20)
          }
          .padding(16)
          .brbCard(radius: 22)
        } else {
          planCard
        }

        notifications
        events
        macs
        security
        privacy
        language
        help
        about
        if store.isDemo { DemoControls().padding(.top, 8) }

        FootNote(symbol: "lock.fill", text: t("noAccount")).padding(.top, 18)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 30)
    }
    .background(Backdrop())
    .navigationTitle(t("tabSettings"))
  }

  // MARK: Plan

  private var planCard: some View {
    VStack(spacing: 14) {
      HStack(spacing: 12) {
        if store.pro {
          Image(systemName: "star.fill")
            .font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(
              LinearGradient(colors: [Color(hex: 0x6f8cff), Color(hex: 0x3a5bd9)], startPoint: .top, endPoint: .bottom),
              in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
          AppMark(size: 44)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(t(store.pro ? "planCloud" : "planFree")).font(.system(size: 17, weight: .bold))
          Text(t(store.pro ? "planProS" : "planFreeS")).font(.system(size: 13)).foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: 10) {
        if !store.pro {
          Button { store.sheet = .paywall } label: { Text(t("upgrade")) }
            .buttonStyle(.big(.tint, height: 42, size: 15))
        }
        Button { restore() } label: { Text(t("restore")) }
          .buttonStyle(.big(.glass, height: 42, size: 15))
      }
    }
    .padding(16)
    .brbCard(radius: 22)
  }

  private func restore() {
    Task {
      let found = await store.entitlements.restore()
      store.show(found ? t("subscribed") : t("restored"), found ? "star.fill" : "info.circle")
    }
  }

  // MARK: Notifications

  private var notifications: some View {
    VStack(spacing: 0) {
      SectionHeader(text: t("g_notif"))
      Grp {
        ToggleRow(
          title: t("n_allow"),
          isOn: Binding(get: { notifOn }, set: { _ in store.fixNotifications() }))
        if Capabilities.criticalAlerts || store.isDemo {
          Hairline(inset: 14)
          ToggleRow(
            title: t("n_crit"), subtitle: t("n_critS"), isOn: Binding(get: { store.criticalAlerts && notifOn }, set: { store.setCritical($0) }),
            dimmed: !notifOn)
        }
      }
    }
  }

  private var events: some View {
    VStack(spacing: 0) {
      SectionHeader(text: t("g_events"))
      Grp {
        ToggleRow(title: t("e_alarm"), subtitle: t("e_alarmS"), isOn: .constant(true), locked: true)
        ForEach(["siren", "back", "disarm", "guard", "sensor"], id: \.self) { key in
          Hairline(inset: 14)
          ToggleRow(
            title: t("e_" + key), isOn: Binding(get: { (store.eventPrefs[key] ?? false) && notifOn }, set: { store.setEvent(key, $0) }),
            dimmed: !notifOn)
        }
        Hairline(inset: 14)
        Button { store.sendSettingsTestPush() } label: {
          HStack {
            Text(t("n_test")).font(.system(size: 15.5, weight: .medium)).foregroundStyle(Theme.tint)
            Spacer()
            Image(systemName: "bell").foregroundStyle(Theme.tint)
          }
          .padding(.horizontal, 14).padding(.vertical, 12)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
      }
    }
  }

  // MARK: Macs

  private var macs: some View {
    VStack(spacing: 0) {
      SectionHeader(text: t("g_macs"))
      Grp {
        if store.macs.isEmpty {
          Text(t("noMacs")).font(.system(size: 14)).foregroundStyle(Theme.ink3)
            .padding(.horizontal, 14).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ForEach(store.macs) { m in
            Button { store.openMac(m) } label: {
              Row(icon: ("laptopcomputer", Theme.gray), title: m.name, subtitle: m.model + " · " + m.snapshot.plain(), chevron: true)
            }
            .buttonStyle(RowButtonStyle())
            Hairline()
          }
        }
        Button { store.addMac() } label: {
          HStack(spacing: 12) {
            RowIcon(symbol: "plus", color: Theme.tint)
            Text(t("pairNew")).font(.system(size: 15.5, weight: .medium)).foregroundStyle(Theme.tint)
            Spacer()
          }
          .padding(.horizontal, 14).padding(.vertical, 11)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
      }
    }
  }

  // MARK: Security, privacy, language, help, about

  private var security: some View {
    VStack(spacing: 0) {
      SectionHeader(text: t("g_sec"))
      Grp {
        ToggleRow(
          title: t("faceReq"), subtitle: t("faceReqS"), isOn: Binding(get: { store.faceRequired }, set: { store.setFaceRequired($0) }))
      }
    }
  }

  private var privacy: some View {
    VStack(spacing: 0) {
      SectionHeader(text: t("g_priv"))
      Grp {
        NavigationLink(value: Route.privacy) { Row(icon: ("eye", Theme.gray), title: t("privRow"), chevron: true) }
          .buttonStyle(RowButtonStyle())
        Hairline()
        Button { confirmDeleteCloud() } label: { Row(icon: ("trash", Theme.gray), title: t("delCloud"), destructive: true) }
          .buttonStyle(RowButtonStyle())
      }
    }
  }

  private var language: some View {
    VStack(spacing: 0) {
      SectionHeader(text: t("g_lang"))
      Grp {
        Button { store.openAppSettings() } label: {
          Row(icon: ("globe", Theme.gray), title: t("langRow"), chevron: true) {
            Text(t("langV") + " · " + (isZh ? "中文" : "English")).font(.system(size: 14)).foregroundStyle(Theme.ink3)
          }
        }
        .buttonStyle(RowButtonStyle())
      }
    }
  }

  private var help: some View {
    VStack(spacing: 0) {
      SectionHeader(text: t("g_help"))
      Grp {
        NavigationLink(value: Route.faq) { Row(icon: ("questionmark.circle", Theme.gray), title: t("faq"), chevron: true) }
          .buttonStyle(RowButtonStyle())
        Hairline()
        Button { UIApplication.shared.open(AppLinks.support) } label: {
          Row(icon: ("envelope", Theme.gray), title: t("contact"), chevron: true)
        }
        .buttonStyle(RowButtonStyle())
        Hairline()
        Button { store.sheet = .sendLink } label: {
          Row(icon: ("laptopcomputer.and.arrow.down", Theme.gray), title: t("sendLink"), chevron: true)
        }
        .buttonStyle(RowButtonStyle())
        Hairline()
        Button { store.onboarding = Onboarding(step: .welcome, extra: true, replay: true) } label: {
          Row(icon: ("arrow.clockwise", Theme.gray), title: t("replay"), chevron: true)
        }
        .buttonStyle(RowButtonStyle())
      }
    }
  }

  private var about: some View {
    VStack(spacing: 0) {
      SectionHeader(text: t("g_about"))
      Grp {
        Row(title: t("version")) { Text(version).font(.system(size: 14)).foregroundStyle(Theme.ink3).monospacedDigit() }
        Hairline(inset: 14)
        Button { UIApplication.shared.open(AppLinks.privacyPolicy) } label: { Row(title: t("pp"), chevron: true) }
          .buttonStyle(RowButtonStyle())
        Hairline(inset: 14)
        Button { UIApplication.shared.open(AppLinks.terms) } label: { Row(title: t("tos"), chevron: true) }
          .buttonStyle(RowButtonStyle())
        Hairline(inset: 14)
        Button {
          if let url = AppLinks.review { UIApplication.shared.open(url) } else { store.show(t("thanks"), "heart.fill") }
        } label: {
          Row(title: t("rate")) { Image(systemName: "star").foregroundStyle(Theme.ink3) }
        }
        .buttonStyle(RowButtonStyle())
      }
    }
  }

  private func confirmDeleteCloud() {
    store.present(
      AlertSpec(
        title: t("delCloudT"), message: t("delCloudP"),
        actions: [
          .init(t("cancel"), role: .cancel),
          .init(t("delete"), role: .destructive) { Task { await store.deleteCloudMedia() } },
        ]))
  }
}

struct ToggleRow: View {
  var title: String
  var subtitle: String?
  @Binding var isOn: Bool
  var dimmed = false
  var locked = false

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 15.5, weight: .medium))
        if let subtitle {
          Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 8)
      Toggle("", isOn: $isOn).labelsHidden().tint(Theme.green).disabled(locked || dimmed)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .opacity(dimmed ? 0.45 : 1)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Privacy and FAQ

struct InfoCard: View {
  var symbol: String
  var title: String
  var text: String
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.tint)
        Text(title).font(.system(size: 15.5, weight: .semibold))
      }
      Text(text).font(.system(size: 14)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .brbCard(radius: 20)
  }
}

struct PrivacyView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        InfoCard(symbol: "eye", title: t("pv_liveT"), text: t("pv_live"))
        InfoCard(symbol: "clock", title: t("pv_whenT"), text: t("pv_when"))
        InfoCard(symbol: "film", title: t("pv_whatT"), text: t("pv_what"))
        InfoCard(symbol: "clock.arrow.circlepath", title: t("pv_howT"), text: t("pv_how"))
        InfoCard(symbol: "circle.dotted", title: t("pv_blurT"), text: t("pv_blur"))
        Grp {
          Button { confirmDelete() } label: { Row(icon: ("trash", Theme.gray), title: t("delCloud"), destructive: true) }
            .buttonStyle(RowButtonStyle())
        }
        .padding(.top, 10)
      }
      .padding(.horizontal, 16)
      .padding(.top, 6)
      .padding(.bottom, 30)
    }
    .background(Backdrop())
    .navigationTitle(t("g_priv"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func confirmDelete() {
    store.present(
      AlertSpec(
        title: t("delCloudT"), message: t("delCloudP"),
        actions: [
          .init(t("cancel"), role: .cancel),
          .init(t("delete"), role: .destructive) { Task { await store.deleteCloudMedia() } },
        ]))
  }
}

struct FAQView: View {
  var body: some View {
    ScrollView {
      VStack(spacing: 10) {
        InfoCard(symbol: "questionmark.circle", title: t("faqQ1"), text: t("faqA1"))
        InfoCard(symbol: "questionmark.circle", title: t("faqQ2"), text: t("faqA2"))
        InfoCard(symbol: "questionmark.circle", title: t("faqQ3"), text: t("faqA3"))
        Grp {
          Button { UIApplication.shared.open(AppLinks.support) } label: {
            Row(icon: ("envelope", Theme.tint), title: t("contact"), chevron: true)
          }
          .buttonStyle(RowButtonStyle())
        }
        .padding(.top, 10)
      }
      .padding(.horizontal, 16)
      .padding(.top, 6)
      .padding(.bottom, 30)
    }
    .background(Backdrop())
    .navigationTitle(t("faq"))
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: - Send the Mac app link

struct SendLinkSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SheetHeader(title: t("sendLink"), subtitle: t("nmP")) { dismiss() }.padding(.bottom, 14)
      LinkOptions()
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 20)
    .padding(.top, 22)
    .presentationDetents([.medium])
  }
}

/// Handoff, Mail, Copy: three ways to get the Mac app's download link onto the Mac.
struct LinkOptions: View {
  @Environment(AppStore.self) private var store
  @State private var sent: String?
  @State private var activity: NSUserActivity?

  var body: some View {
    VStack(spacing: 8) {
      LinkOption(symbol: "macbook.and.iphone", title: t("nm_handoff"), subtitle: t("nm_handoffS"), done: sent == "handoff") { handoff() }
      LinkOption(symbol: "envelope", title: t("nm_mail"), subtitle: t("nm_mailS"), done: sent == "mail") { mail() }
      LinkOption(symbol: "link", title: t("nm_copy"), subtitle: t("nm_copyS"), done: sent == "copy") { copy() }
    }
    .onDisappear { activity?.invalidate() }
  }

  private func handoff() {
    let a = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
    a.webpageURL = AppLinks.macDownload
    a.isEligibleForHandoff = true
    a.becomeCurrent()
    activity = a
    sent = "handoff"
    store.show(t("nm_sent"), "paperplane")
  }

  private func mail() {
    var c = URLComponents(string: "mailto:")!
    c.queryItems = [
      URLQueryItem(name: "subject", value: "BRB for Mac"), URLQueryItem(name: "body", value: AppLinks.macDownload.absoluteString),
    ]
    if let url = c.url { UIApplication.shared.open(url) }
    sent = "mail"
  }

  private func copy() {
    UIPasteboard.general.string = AppLinks.macDownload.absoluteString
    sent = "copy"
    store.show(t("nm_copied"), "doc.on.doc")
  }
}

struct LinkOption: View {
  var symbol: String
  var title: String
  var subtitle: String
  var done: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Theme.ink)
          .frame(width: 38, height: 38).background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Theme.ink)
          Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.ink2).multilineTextAlignment(.leading)
        }
        Spacer(minLength: 6)
        if done {
          Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 22, height: 22).background(Theme.tint, in: Circle())
        } else {
          Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3)
        }
      }
      .padding(.horizontal, 14).padding(.vertical, 12)
      .brbCard(radius: 18)
    }
    .buttonStyle(PressableStyle())
  }
}

// MARK: - Demo

/// Only in the demo: play out what a Mac would do, so every screen can be tried without one.
struct DemoControls: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    VStack(spacing: 0) {
      SectionHeader(text: "Demo")
      Grp {
        VStack(alignment: .leading, spacing: 10) {
          Text("Make the demo Mac react").font(.system(size: 13)).foregroundStyle(Theme.ink2)
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(
              [("bump", "Bump"), ("touch", "Touch"), ("lift", "Lift"), ("back", "Put back"), ("finger", "Touch ID"), ("offline", "Offline")],
              id: \.0
            ) { key, title in
              Button { play(key) } label: {
                Text(title).font(.system(size: 13.5, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 38)
                  .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              }
              .buttonStyle(PressableStyle())
            }
          }
        }
        .padding(14)
        Hairline(inset: 14)
        Button { store.leaveDemo() } label: { Row(title: "Leave the demo", chevron: true) }
          .buttonStyle(RowButtonStyle())
      }
    }
  }

  private func play(_ what: String) {
    guard let mac = store.focusMac else { return }
    store.demo?.simulate(what, mac: mac.id)
  }
}
