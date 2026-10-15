import SwiftUI

struct DevicesView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        if store.notif == .denied && !store.macs.isEmpty { NotifBar() }
        if store.pageState == "offline" { OfflineBar(text: t("obarPhone")) }
        if store.pageState == "error" || store.loadFailed {
          ErrorBanner(title: t("errT"), message: t("errS")) { Task { await store.refreshAll() } }
        }
        if store.pageState == "loading" {
          SkeletonCard()
          SkeletonCard()
        } else if store.macs.isEmpty || store.pageState == "empty" {
          empty
        } else {
          ForEach(store.macs) { mac in
            DeviceCard(mac: mac)
          }
          Button { store.addMac() } label: {
            HStack(spacing: 10) {
              Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
              Text(t("addMac")).font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Theme.ink2)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .overlay(
              RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.rim, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
          }
          .buttonStyle(PressableStyle())
          FootNote(symbol: "lock.fill", text: t("privFoot")).padding(.top, 6)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 6)
      .padding(.bottom, 30)
    }
    .background(Backdrop())
    .navigationTitle(t("tabDevices"))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        RoundIconButton(symbol: "plus", label: t("pairNew")) { store.addMac() }
      }
    }
    .refreshable { await store.refreshAll() }
  }

  private var empty: some View {
    VStack(spacing: 0) {
      EmptyState(title: t("emptyDevT"), message: t("emptyDevP")) { PairArt() }
      Button { store.addMac() } label: {
        HStack(spacing: 8) {
          Image(systemName: "qrcode.viewfinder")
          Text(t("emptyDevT"))
        }
      }
      .buttonStyle(.big(.tint))
      .padding(.horizontal, 24)
      .padding(.top, 22)
      Button(t("emptyDevLnk")) { store.onboarding = Onboarding(step: .nomac, extra: true) }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.tint)
        .padding(.top, 16)
    }
  }
}

/// Notifications are off: say so, and say how to fix it.
struct NotifBar: View {
  @Environment(AppStore.self) private var store
  var body: some View {
    Button { store.fixNotifications() } label: {
      HStack(spacing: 10) {
        Image(systemName: "bell.slash.fill")
        Text(t("ybar")).font(.system(size: 13.5, weight: .medium)).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
        Text(t("ybarBtn")).font(.system(size: 13.5, weight: .bold))
      }
      .foregroundStyle(Theme.yellowInk)
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(Theme.yellowBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(PressableStyle())
  }
}

struct SkeletonCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 10) {
        Skeleton(width: 34, height: 34, radius: 10)
        Skeleton(width: 170, height: 14)
        Spacer()
      }
      HStack(spacing: 14) {
        Skeleton(width: 58, height: 58, radius: 18)
        VStack(alignment: .leading, spacing: 8) {
          Skeleton(width: 130, height: 20)
          Skeleton(width: 180, height: 12)
        }
        Spacer()
      }
      Skeleton(height: 44, radius: 22)
    }
    .padding(16)
    .brbCard(radius: 26)
  }
}

// MARK: - A Mac's card

struct DeviceCard: View {
  @Environment(AppStore.self) private var store
  var mac: MacModel

  private var look: Look { mac.look }

  var body: some View {
    if mac.isLoading {
      SkeletonCard()
    } else {
      card
    }
  }

  private var card: some View {
    TimelineView(.periodic(from: .now, by: 1)) { ctx in
      let now = ctx.date.ms
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "laptopcomputer")
            .font(.system(size: 17))
            .foregroundStyle(Theme.ink2)
            .frame(width: 34, height: 34)
            .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          VStack(alignment: .leading, spacing: 0) {
            Text(mac.name).font(.system(size: 15.5, weight: .semibold)).lineLimit(1)
            Text(mac.model).font(.system(size: 12)).foregroundStyle(Theme.ink3).lineLimit(1)
          }
          Spacer(minLength: 8)
          if let info = mac.state.mac, look != .offline {
            BatteryView(pct: info.batt, charging: info.chg).foregroundStyle(Theme.ink2)
          }
        }

        HStack(spacing: 14) {
          ShieldView(look: look.shield, size: 58, progress: mac.armProgress(now: now))
            .foregroundStyle(Theme.ink2)
            .frame(width: 58, height: 58)
          VStack(alignment: .leading, spacing: 3) {
            Text(mac.snapshot.title(now: now))
              .font(.system(size: 23, weight: .bold))
              .foregroundStyle(Theme.text(for: look))
              .lineLimit(2)
              .minimumScaleFactor(0.8)
            Text(mac.snapshot.subtitle(now: now))
              .font(.system(size: 13.5))
              .foregroundStyle(Theme.ink2)
              .monospacedDigit()
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .padding(.bottom, 14)

        HStack(spacing: 10) {
          Chip(symbol: mac.state.place.symbol, text: mac.state.place.name)
          MainButton(mac: mac)
        }
      }
      .padding(.top, 16)
      .padding(.horizontal, 16)
      .padding(.bottom, 14)
      .background(glow)
      .brbCard(radius: 26)
      .overlay(alarmRim)
      .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
      .opacity(look == .offline ? 0.72 : 1)
      .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
      .onTapGesture { store.openMac(mac) }
      .accessibilityElement(children: .contain)
    }
  }

  @ViewBuilder private var glow: some View {
    switch look {
    case .armed, .partial, .test:
      RadialGradient(colors: [Theme.amber.opacity(0.22), .clear], center: .init(x: 0.12, y: 0.35), startRadius: 0, endRadius: 150)
    case .alarm:
      RadialGradient(colors: [Theme.red.opacity(0.2), .clear], center: .init(x: 0.18, y: 0.5), startRadius: 0, endRadius: 260)
    case .warn:
      RadialGradient(colors: [Theme.orange.opacity(0.18), .clear], center: .init(x: 0.18, y: 0.5), startRadius: 0, endRadius: 260)
    default:
      Color.clear
    }
  }

  @ViewBuilder private var alarmRim: some View {
    switch look {
    case .alarm:
      RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.red.opacity(0.55), lineWidth: 1.5)
    case .warn:
      RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.orange.opacity(0.55), lineWidth: 1.5)
    default:
      EmptyView()
    }
  }
}

extension MacModel {
  /// No answer yet and nothing remembered: show the card as a placeholder.
  var isLoading: Bool { link == .connecting && snapshot.lastSeen == 0 && snapshot.view.state == nil }

  /// How far the arming countdown has run, for the rising fill of the shield.
  func armProgress(now: Ms) -> Double {
    guard look == .arming, let end = state.armEnd else { return 0.5 }
    let start = state.since > 0 ? state.since : end - 10_000
    return (Double(now - start) / Double(max(1, end - start))).clamped()
  }
}

// MARK: - The one big button a Mac has

struct MainButton: View {
  @Environment(AppStore.self) private var store
  var mac: MacModel
  /// On the Mac's own page: taller, and "stop" even when only partly guarding.
  var big = false

  private var height: CGFloat { big ? 52 : 44 }
  private var size: CGFloat { big ? 17 : 15.5 }

  private func label(_ text: String, _ symbol: String?) -> some View {
    HStack(spacing: 7) {
      if let symbol { Image(systemName: symbol) }
      Text(text).lineLimit(1).minimumScaleFactor(0.8)
    }
  }

  var body: some View {
    switch mac.look {
    case .idle:
      Button { store.sheet = .start(mac.id) } label: { label(t("btn_start"), "shield") }
        .buttonStyle(.big(.amber, height: height, size: size))
    case .arming:
      Button { Task { await store.cancelArming(mac) } } label: { label(t("btn_cancel"), nil) }
        .buttonStyle(.big(.glass, height: height, size: size))
    case .armed:
      stop
    case .partial:
      if big {
        stop
      } else {
        Button { store.openMac(mac) } label: { label(t("btn_why"), "info.circle") }
          .buttonStyle(.big(.glass, height: height, size: size))
      }
    case .test:
      Button { Task { await store.stopGuarding(mac) } } label: { label(t("btn_stop"), nil) }
        .buttonStyle(.big(.glass, height: height, size: size))
    case .offline:
      if !big {
        Text(t("offNote")).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).multilineTextAlignment(.trailing)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    case .alarm, .warn:
      Button { store.openAlarm(mac) } label: { label(t("btn_openAlarm"), "exclamationmark.triangle") }
        .buttonStyle(.big(.red, height: height, size: size))
    }
  }

  private var stop: some View {
    Button { Task { await store.stopGuarding(mac) } } label: {
      label(t("btn_stopGuard"), store.faceRequired ? "faceid" : nil)
    }
    .buttonStyle(.big(.glass, height: height, size: size))
  }
}

// MARK: - A Mac's page

struct MacDetailView: View {
  @Environment(AppStore.self) private var store
  var macID: String

  var body: some View {
    if let mac = store.mac(macID) {
      MacDetailBody(mac: mac)
    } else {
      Color.clear.background(Backdrop())
    }
  }
}

struct MacDetailBody: View {
  @Environment(AppStore.self) private var store
  var mac: MacModel
  @State private var note = ""
  @State private var vol = 80.0
  @State private var editingVolume = false
  @State private var place: Place = .cafe
  @FocusState private var noteFocused: Bool

  private var look: Look { mac.look }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        if store.pageState == "offline" { OfflineBar(text: t("obarPhone")).padding(.bottom, 10) }
        if store.pageState == "error" {
          ErrorBanner(title: t("errT"), message: t("errS")) { Task { await store.refreshAll() } }.padding(.bottom, 10)
        }
        if store.pageState == "loading" || mac.isLoading {
          loading
        } else {
          hero
          settings
          health
          recent
          actions
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 30)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(Backdrop())
    .navigationTitle(mac.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Button { rename() } label: { Label(t("mdRename"), systemImage: "pencil") }
          Button { resetLink() } label: { Label(t("mdReset"), systemImage: "arrow.clockwise") }
          Button(role: .destructive) { unpair() } label: { Label(t("mdUnpair"), systemImage: "link.badge.plus") }
        } label: {
          Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
        }
        .accessibilityLabel(t("mdSettings"))
      }
    }
    .task {
      sync()
      await store.loadHistory(mac)
    }
    .onChange(of: mac.state.note) { _, v in if !noteFocused { note = v } }
    .onChange(of: mac.state.vol) { _, v in if !editingVolume { vol = Double(v) } }
    .onChange(of: mac.state.place) { _, v in place = v }
  }

  private func sync() {
    note = mac.state.note
    vol = Double(mac.state.vol)
    place = mac.state.place
  }

  private var loading: some View {
    VStack(spacing: 12) {
      Skeleton(width: 84, height: 84, radius: 30).padding(.top, 14)
      Skeleton(width: 140, height: 26)
      Skeleton(width: 200, height: 14)
      Skeleton(height: 52, radius: 26).padding(.horizontal, 20)
      ForEach(0..<3, id: \.self) { _ in Skeleton(height: 54, radius: 16) }
    }
  }

  // MARK: Hero

  private var hero: some View {
    TimelineView(.periodic(from: .now, by: 1)) { ctx in
      let now = ctx.date.ms
      VStack(spacing: 0) {
        ShieldView(look: look.shield, size: 84, progress: mac.armProgress(now: now))
          .foregroundStyle(Theme.ink2)
          .frame(width: 96, height: 96)
          .padding(.bottom, 6)
        Text(mac.snapshot.title(now: now))
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(Theme.text(for: look))
          .multilineTextAlignment(.center)
        Text(mac.snapshot.subtitle(now: now) + (look == .offline ? "" : " · " + mac.state.place.name))
          .font(.system(size: 14.5))
          .foregroundStyle(Theme.ink2)
          .monospacedDigit()
          .multilineTextAlignment(.center)
          .padding(.top, 4)
          .padding(.bottom, 16)
        MainButton(mac: mac, big: true).frame(maxWidth: 300)
        HStack(spacing: 6) {
          Image(systemName: "lock.fill").font(.system(size: 11))
          Text(t("privFoot")).font(.system(size: 12.5))
        }
        .foregroundStyle(Theme.ink3)
        .padding(.top, 12)
      }
      .padding(.top, 14)
      .padding(.horizontal, 20)
      .frame(maxWidth: .infinity)
    }
  }

  // MARK: Settings

  private var settings: some View {
    VStack(spacing: 0) {
      SectionHeader(text: t("mdSettings"))
      Grp {
        VStack(alignment: .leading, spacing: 8) {
          Text(t("kv_place")).font(.system(size: 15.5, weight: .medium))
          Seg(
            options: Place.allCases.map { (value: $0, title: $0.name, symbol: Optional($0.symbol)) },
            selection: Binding(
              get: { place },
              set: { new in
                place = new
                Task { await store.send(.set(place: new, note: nil, vol: nil, test: nil), to: mac) }
              }))
          Text(place.detail).font(.system(size: 12.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        Hairline(inset: 14)
        HStack(spacing: 10) {
          Text(t("mdNote")).font(.system(size: 15.5, weight: .medium))
          TextField(t("shNotePh"), text: $note)
            .focused($noteFocused)
            .multilineTextAlignment(.trailing)
            .submitLabel(.done)
            .onChange(of: note) { _, v in if v.count > 40 { note = String(v.prefix(40)) } }
            .onSubmit { commitNote() }
            .onChange(of: noteFocused) { _, f in if !f { commitNote() } }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        Hairline(inset: 14)
        VStack(spacing: 8) {
          HStack {
            Text(t("mdVol")).font(.system(size: 15.5, weight: .medium))
            Spacer()
            Text(mac.state.test ? t("lb_test") : "\(Int(vol))%").font(.system(size: 15)).foregroundStyle(Theme.ink2).monospacedDigit()
          }
          HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.system(size: 13)).foregroundStyle(Theme.ink3)
            Slider(value: $vol, in: 0...100, step: 1) { editing in
              editingVolume = editing
              if !editing { Task { await store.send(.set(place: nil, note: nil, vol: Int(vol), test: nil), to: mac) } }
            }
            .disabled(mac.state.test)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 13)).foregroundStyle(Theme.ink3)
          }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        Hairline(inset: 14)
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 1) {
            Text(t("mdTest")).font(.system(size: 15.5, weight: .medium))
            Text(t("mdTestS")).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 8)
          Toggle(
            "",
            isOn: Binding(
              get: { mac.state.test },
              set: { on in Task { await store.send(.set(place: nil, note: nil, vol: nil, test: on), to: mac) } })
          )
          .labelsHidden()
          .tint(Theme.green)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
      }
      SectionFooter(text: t("mdSync"))
    }
  }

  private func commitNote() {
    let clean = note.trimmingCharacters(in: .whitespaces)
    guard clean != mac.state.note else { return }
    Task { await store.send(.set(place: nil, note: clean, vol: nil, test: nil), to: mac) }
  }

  // MARK: Health

  private var health: some View {
    let bad = mac.state.health.failing
    return VStack(spacing: 0) {
      SectionHeader(text: t("mdHealth") + " · " + (bad.isEmpty ? t("mdHealthOk") : t("mdHealthBad", bad.count)))
      Grp {
        ForEach(Array(Health.keys.enumerated()), id: \.element) { i, key in
          if i > 0 { Hairline(inset: 56) }
          HealthRow(key: key, ok: mac.state.health[key])
        }
      }
    }
  }

  // MARK: Recent sessions

  private var recent: some View {
    let rs = Array(mac.sessions.prefix(3))
    return VStack(spacing: 0) {
      SectionHeader(
        text: t("mdRecent"),
        trailing: rs.isEmpty
          ? nil
          : (title: t("mdAll"), action: { store.recordMac = mac.id; store.tab = .records }))
      Grp {
        if rs.isEmpty {
          Text(t("mdNoRec")).font(.system(size: 14)).foregroundStyle(Theme.ink3)
            .padding(.horizontal, 14).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ForEach(Array(rs.enumerated()), id: \.element.id) { i, r in
            if i > 0 { Hairline() }
            RecordRow(mac: mac, record: r, showDay: true)
          }
        }
      }
    }
  }

  // MARK: Rename, reset, unpair

  private var actions: some View {
    Grp {
      Button { rename() } label: { Row(icon: ("pencil", Theme.gray), title: t("mdRename"), chevron: true) }
        .buttonStyle(RowButtonStyle())
      Hairline()
      Button { resetLink() } label: {
        Row(icon: ("arrow.clockwise", Theme.gray), title: t("mdReset"), subtitle: t("mdResetS"), chevron: true)
      }
      .buttonStyle(RowButtonStyle())
      Hairline()
      Button { unpair() } label: { Row(icon: ("link.badge.plus", Theme.gray), title: t("mdUnpair"), destructive: true) }
        .buttonStyle(RowButtonStyle())
    }
    .padding(.top, 22)
  }

  private func rename() {
    store.present(
      AlertSpec(
        title: t("renameT"), message: nil, input: mac.name,
        actions: [
          .init(t("cancel"), role: .cancel),
          .init(t("done")) { store.rename(mac, to: store.alertInput) },
        ]))
  }

  private func resetLink() {
    store.present(
      AlertSpec(
        title: t("resetT"), message: t("resetP"),
        actions: [
          .init(t("cancel"), role: .cancel),
          .init(t("mdReset"), role: .destructive) {
            Task {
              if case .failed = await store.send(.reset, to: mac) { return }
              store.show(t("resetDone"), "arrow.clockwise")
            }
          },
        ]))
  }

  private func unpair() {
    store.present(
      AlertSpec(
        title: t("mdUnpair"), message: t("unpairT"),
        actions: [
          .init(t("cancel"), role: .cancel),
          .init(t("mdUnpair"), role: .destructive) { store.unpair(mac) },
        ]))
  }
}

struct HealthRow: View {
  var key: String
  var ok: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: ok ? "checkmark" : "exclamationmark")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(ok ? Theme.ink2 : Theme.textRed)
        .frame(width: 30, height: 30)
        .background(ok ? Theme.cardHi : Theme.red.opacity(0.16), in: Circle())
      VStack(alignment: .leading, spacing: 1) {
        Text(t("h_" + key)).font(.system(size: 15.5, weight: .medium)).foregroundStyle(ok ? Theme.ink : Theme.textRed)
        Text(t("h_" + key + (ok ? "_ok" : "_bad"))).font(.system(size: 12.5)).foregroundStyle(Theme.ink3)
          .fixedSize(horizontal: false, vertical: true)
        if !ok {
          Text(t("h_" + key + "_fix"))
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 6)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Start guarding

struct StartSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var mac: MacModel
  @State private var place = Prefs.lastPlace
  @State private var note = Prefs.lastNote
  @State private var sending = false
  @State private var started = false

  private enum Stage { case form, countdown, guarding }

  private var stage: Stage {
    if mac.look == .arming { return .countdown }
    if started && mac.look.isGuarding { return .guarding }
    return .form
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(t("shStartT")).font(.system(size: 21, weight: .bold))
          Text(mac.name).font(.system(size: 13.5)).foregroundStyle(Theme.ink2)
        }
        Spacer()
        RoundIconButton(symbol: "xmark", label: t("cancel")) { dismiss() }
      }
      .padding(.bottom, 14)

      switch stage {
      case .form: form
      case .countdown: countdown
      case .guarding: guarding
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 20)
    .padding(.top, 22)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .onChange(of: mac.look) { old, new in
      if new == .arming { started = true }
      if old == .arming && new == .idle { dismiss() }
      if started && new.isGuarding {
        Task {
          try? await Task.sleep(nanoseconds: 1_700_000_000)
          dismiss()
        }
      }
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(sending)
  }

  // MARK: Form

  private var form: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(t("shPlace")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2).padding(.horizontal, 4).padding(.bottom, 8)
      VStack(spacing: 8) {
        ForEach(Place.allCases, id: \.self) { p in PlaceOption(place: p, selected: place == p) { place = p } }
      }
      Text(t("shNote")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
        .padding(.horizontal, 4).padding(.top, 16).padding(.bottom, 8)
      HStack(spacing: 10) {
        Image(systemName: "text.bubble").foregroundStyle(Theme.ink3)
        TextField(t("shNotePh"), text: $note)
          .submitLabel(.done)
          .onChange(of: note) { _, v in if v.count > 40 { note = String(v.prefix(40)) } }
      }
      .padding(.horizontal, 14).frame(height: 48)
      .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      Text(t("shNoteHint")).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).padding(.horizontal, 4).padding(.top, 7)
      Button { go() } label: {
        HStack(spacing: 8) {
          if sending { ProgressView().tint(Theme.amberInk) } else { Image(systemName: "shield") }
          Text(t("shGo"))
        }
      }
      .buttonStyle(.big(.amber))
      .disabled(sending)
      .padding(.top, 18)
    }
  }

  private func go() {
    sending = true
    Task {
      let result = await store.startGuarding(mac, place: place, note: note.trimmingCharacters(in: .whitespaces))
      sending = false
      switch result {
      case .done: started = true
      case .queued: dismiss()
      case .failed: break
      }
    }
  }

  // MARK: Countdown

  private var countdown: some View {
    TimelineView(.animation(minimumInterval: 0.05)) { ctx in
      let now = ctx.date.ms
      let end = mac.state.armEnd ?? now
      let start = mac.state.since > 0 ? mac.state.since : end - 10_000
      let progress = (Double(now - start) / Double(max(1, end - start))).clamped()
      let left = mac.snapshot.secsLeft(until: mac.state.armEnd, now: now)
      VStack(spacing: 0) {
        ZStack {
          Circle().stroke(Theme.hair, lineWidth: 4).padding(2)
          Circle().trim(from: 0, to: progress).stroke(Theme.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90)).padding(2)
          ShieldView(look: .arming, size: 118, progress: progress).foregroundStyle(Theme.ink2)
        }
        .frame(width: 150, height: 150)
        Text("\(left)").font(.system(size: 64, weight: .ultraLight, design: .rounded)).monospacedDigit().padding(.top, 8)
        Text(t("cdWalk")).font(.system(size: 19, weight: .semibold)).padding(.top, 4)
        Text(t("cdSub")).font(.system(size: 14)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center).padding(.top, 2)
        Button { Task { await store.cancelArming(mac) } } label: { Text(t("btn_cancel")) }
          .buttonStyle(.big(.glass))
          .padding(.top, 18)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var guarding: some View {
    VStack(spacing: 0) {
      ShieldView(look: mac.look.shield, size: 118).foregroundStyle(Theme.ink2).frame(width: 150, height: 150)
      Text(t("cdOnT")).font(.system(size: 19, weight: .semibold)).padding(.top, 6)
      Text(t("cdOnS", mac.state.place.name)).font(.system(size: 14)).foregroundStyle(Theme.ink2).padding(.top, 2)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 30)
  }
}

struct PlaceOption: View {
  var place: Place
  var selected: Bool
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: place.symbol)
          .font(.system(size: 18))
          .foregroundStyle(Theme.ink)
          .frame(width: 38, height: 38)
          .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        VStack(alignment: .leading, spacing: 1) {
          Text(place.name).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Theme.ink)
          Text(place.detail).font(.system(size: 12.5)).foregroundStyle(Theme.ink2).multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 6)
        ZStack {
          Circle().strokeBorder(selected ? Color.clear : Theme.rim, lineWidth: 1.5)
          if selected {
            Circle().fill(Theme.tint)
            Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
          }
        }
        .frame(width: 22, height: 22)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(selected ? Theme.tintBg : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Theme.tint : Theme.cardBorder, lineWidth: 1.5)
      )
    }
    .buttonStyle(PressableStyle())
  }
}
