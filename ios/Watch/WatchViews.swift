import SwiftUI

// MARK: - Root

/// The Watch app's first screen: the Pro page, the empty page, one Mac, or a vertical pager of Macs.
struct WRootView: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    NavigationStack {
      content
    }
    .overlay(alignment: .bottom) {
      WNoticeView(model: model)
    }
    .animation(.default, value: model.notice)
  }

  @ViewBuilder
  private var content: some View {
    if !model.pro {
      WCloudView()
    } else if model.macs.isEmpty {
      WEmptyView()
    } else if model.macs.count == 1 {
      WMacPage(model: model, id: model.macs[0].id)
    } else {
      TabView(selection: $model.selected) {
        ForEach(model.macs) { mac in
          WMacPage(model: model, id: mac.id)
            .tag(mac.id)
        }
      }
      .tabViewStyle(.verticalPage)
    }
  }
}

// MARK: - One Mac

/// What one Mac looks like on the wrist: the green "clear" shield, the alarm, the countdown, or the status.
struct WMacPage: View {
  @ObservedObject var model: WatchModel
  let id: String
  @State private var showPlaces = false

  var body: some View {
    let snap = model.snapshot(for: id)
    Group {
      if let done = model.finished[id] {
        WDoneView(done: done)
      } else if snap.state.phase == .triggered {
        WAlarmView(model: model, id: id)
      } else if !model.hasState(id) {
        WWaitView(model: model, id: id)
      } else if snap.look == .arming {
        WCountdownView(model: model, id: id)
      } else {
        WStatusView(model: model, id: id, showPlaces: $showPlaces)
      }
    }
    .navigationDestination(isPresented: $showPlaces) {
      WPlaceList(current: snap.state.place) { place in
        showPlaces = false
        Task { await model.send(.start(place: place, note: nil, test: nil), to: id) }
      }
    }
  }
}

// MARK: - Status

/// Not guarding, guarding, or offline: the shield, the word, the line under it and the one button.
struct WStatusView: View {
  @ObservedObject var model: WatchModel
  let id: String
  @Binding var showPlaces: Bool
  @State private var confirmStop = false
  @State private var glow = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let snap = model.snapshot(for: id)
    GeometryReader { geo in
      let small = geo.size.height < 178
      VStack(spacing: 3) {
        if model.macs.count > 1 {
          Text(snap.name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.ink2)
            .lineLimit(1)
        }
        ZStack {
          Circle()
            .fill(RadialGradient(colors: [Theme.amber.opacity(0.34), Color.clear], center: .center, startRadius: 0, endRadius: 48))
            .frame(width: 96, height: 96)
            .opacity(snap.look.isGuarding ? (glow ? 1 : 0.45) : 0)
            .animation(breathe, value: glow)
          ShieldView(look: snap.look.shield, size: small ? 42 : 54)
            .foregroundStyle(Theme.ink)
        }
        .frame(height: small ? 46 : 60)
        .onAppear { glow = true }

        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
          VStack(spacing: 1) {
            Text(snap.title(now: ctx.date.ms))
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(Theme.text(for: snap.look))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
            Text(snap.subtitle(now: ctx.date.ms))
              .font(.system(size: 12))
              .foregroundStyle(Theme.ink2)
              .multilineTextAlignment(.center)
              .lineLimit(small ? 1 : 2)
              .minimumScaleFactor(0.85)
          }
        }
        if model.lost.contains(id) {
          Text(t("errT"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textOrange)
            .lineLimit(1)
        }
        Spacer(minLength: 2)
        mainButton(snap)
      }
      .padding(.horizontal, 4)
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .confirmationDialog(t("btn_stopGuard"), isPresented: $confirmStop, titleVisibility: .visible) {
      Button(t("btn_stopGuard"), role: .destructive) {
        Task { await model.send(.stop, to: id, done: "toastStop") }
      }
      Button(t("btn_cancel"), role: .cancel) {}
    }
  }

  private var breathe: Animation? {
    if reduceMotion { return nil }
    return Animation.easeInOut(duration: 2.1).repeatForever(autoreverses: true)
  }

  @ViewBuilder
  private func mainButton(_ snap: MacSnapshot) -> some View {
    let working = model.busy.contains(id)
    switch snap.look {
    case .idle:
      Button {
        showPlaces = true
      } label: {
        WLabel(symbol: "shield.fill", text: t("btn_start"))
      }
      .buttonStyle(WPillStyle.amber)
      .disabled(working)
    case .armed, .partial, .test:
      Button {
        confirmStop = true
      } label: {
        WLabel(symbol: "stop.fill", text: t("btn_stopGuard"))
      }
      .buttonStyle(WPillStyle.white)
      .disabled(working)
    case .arming:
      Button {
        Task { await model.send(.stop, to: id, done: "toastCancel") }
      } label: {
        Text(t("btn_cancel"))
      }
      .buttonStyle(WPillStyle.gray)
      .disabled(working)
    case .offline:
      Button {
      } label: {
        Text(t("st_offline"))
      }
      .buttonStyle(WPillStyle.dim)
      .disabled(true)
    case .warn, .alarm:
      EmptyView()
    }
  }
}

// MARK: - Countdown

/// "Walk away": the ring runs down the Mac's five seconds before it starts guarding.
struct WCountdownView: View {
  @ObservedObject var model: WatchModel
  let id: String

  var body: some View {
    let snap = model.snapshot(for: id)
    TimelineView(.periodic(from: Date(), by: 0.5)) { ctx in
      let now = ctx.date.ms
      let end = snap.state.armEnd ?? now
      let left = min(99, snap.secsLeft(until: snap.state.armEnd, now: now))
      let progress = (1 - Double(end - now) / 5000).clamped()
      VStack(spacing: 4) {
        ZStack {
          Circle()
            .stroke(Theme.amber.opacity(0.18), lineWidth: 7)
          Circle()
            .trim(from: 0, to: progress)
            .stroke(Theme.amber, style: StrokeStyle(lineWidth: 7, lineCap: .round))
            .rotationEffect(.degrees(-90))
          Text(String(left))
            .font(.rounded(38, .semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.amber)
        }
        .frame(width: 84, height: 84)
        Text(t("wv_walk"))
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(Theme.ink)
        WCaption(text: t("wv_sync"))
        Spacer(minLength: 2)
        Button {
          Task { await model.send(.stop, to: id, done: "toastCancel") }
        } label: {
          Text(t("btn_cancel"))
        }
        .buttonStyle(WPillStyle.gray)
        .disabled(model.busy.contains(id))
      }
      .padding(.horizontal, 4)
    }
  }
}

// MARK: - Places

/// Library, café or on the go. Picking one starts the countdown.
struct WPlaceList: View {
  let current: Place
  let onPick: (Place) -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 6) {
        ForEach(Place.allCases, id: \.self) { place in
          Button {
            onPick(place)
          } label: {
            row(place)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 4)
    }
    .navigationTitle(t("wv_place"))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func row(_ place: Place) -> some View {
    let on = place == current
    return HStack(spacing: 9) {
      ZStack {
        Circle()
          .fill(on ? Theme.tint : Theme.tint.opacity(0.2))
        Image(systemName: place.symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(on ? Color(hex: 0x0b1020) : Theme.tint)
      }
      .frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 1) {
        Text(place.name)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.ink)
        Text(place.detail)
          .font(.system(size: 11))
          .foregroundStyle(Theme.ink2)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 15).fill(Color(white: 1, opacity: 0.1)))
  }
}

// MARK: - Waiting, empty, Pro

/// Before the relay has said anything about a Mac.
struct WWaitView: View {
  @ObservedObject var model: WatchModel
  let id: String

  var body: some View {
    VStack(spacing: 6) {
      ShieldView(look: .offline, size: 46)
        .foregroundStyle(Theme.ink)
      if model.lost.contains(id) {
        Text(t("errT"))
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(Theme.ink)
          .multilineTextAlignment(.center)
        WCaption(text: t("errS"))
      } else {
        ProgressView()
      }
    }
    .padding(.horizontal, 6)
  }
}

/// Nothing is paired yet.
struct WEmptyView: View {
  var body: some View {
    VStack(spacing: 6) {
      ShieldView(look: .idle, size: 50)
        .foregroundStyle(Theme.ink)
      Text(t("ww_emptyT"))
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(Theme.ink)
        .multilineTextAlignment(.center)
      WCaption(text: t("ww_emptyS"))
    }
    .padding(.horizontal, 6)
  }
}

/// Without Pro the Watch app only says what Pro adds. Notifications still mirror from the iPhone.
struct WCloudView: View {
  var body: some View {
    ScrollView {
      VStack(spacing: 6) {
        ZStack {
          Circle().fill(Theme.tint.opacity(0.2))
          Image(systemName: "applewatch")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.tint)
        }
        .frame(width: 44, height: 44)
        Text(t("wv_cloudT"))
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(Theme.ink)
          .multilineTextAlignment(.center)
        WCaption(text: t("wv_cloudS"))
        HStack(spacing: 5) {
          Image(systemName: "iphone")
          Text(t("wv_cloudBtn"))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.tint)
        .padding(.top, 4)
      }
      .padding(.horizontal, 6)
    }
  }
}

// MARK: - Notice

/// The line that shows for a moment after a command. It never takes taps.
struct WNoticeView: View {
  @ObservedObject var model: WatchModel

  var body: some View {
    if let n = model.notice {
      Text(n.text)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(n.good ? Color(white: 0.22) : Theme.flood))
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
        .allowsHitTesting(false)
    }
  }
}
