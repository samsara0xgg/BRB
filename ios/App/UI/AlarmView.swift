import SwiftUI

/// The page that takes over the phone when a Mac is touched: what happened, the live picture, and the two
/// buttons that matter.
struct AlarmView: View {
  @Environment(AppStore.self) private var store
  var mac: MacModel
  @State private var full = false
  @State private var zoom = false
  @State private var summaryAt: Ms = 0

  private var finished: FinishedAlarm? { mac.finished }
  private var phase: AlarmPhase? { finished != nil ? .done : mac.snapshot.alarmPhase }
  private var isDone: Bool { finished != nil }
  private var isTest: Bool { finished?.test ?? mac.state.test }
  private var offline: Bool { !isDone && !mac.online }
  private var hasCamera: Bool { mac.state.health.cam && mac.state.camera }

  /// The thief picked it up again after it was put back.
  private var relifted: Bool {
    let last = mac.state.events.last { $0.e == "lift" || $0.e == "triggered" || $0.e == "back" }
    return last?.e == "lift"
  }

  private var headline: String {
    if isDone { return t("alH_done") }
    let kind = relifted ? "alH_relift" : "alH_" + mac.snapshot.trigger.rawValue
    return (isTest ? t("alTestPre") : "") + t(kind)
  }

  private var photos: [Ms] {
    if let f = finished { return Array(f.photos.reversed()) }
    return mac.alarmPhotos
  }

  var body: some View {
    ZStack {
      Theme.bg.ignoresSafeArea()
      VStack(spacing: 0) {
        AlarmHeader(
          mac: mac, phase: phase, headline: headline, test: isTest, done: isDone, finished: finished, offline: offline,
          close: { store.closeAlarm() })
        if let f = finished {
          AlarmSummary(mac: mac, finished: f, since: summaryAt) {
            store.closeAlarm()
          }
        } else {
          AlarmMedia(
            mac: mac, phase: phase, photos: photos, hasCamera: hasCamera, offline: offline, zoom: $zoom, full: $full,
            headline: headline
          )
          .aspectRatio(16.0 / 10.0, contentMode: .fit)
          .frame(maxWidth: .infinity)
          AlarmLabel(mac: mac, phase: phase, offline: offline, test: isTest)
          timeline
          secondary
          actions
        }
      }
      if isTest && !isDone { TestWatermark() }
      if full && hasCamera && !isDone {
        LiveFullscreen(mac: mac, phase: phase, headline: headline, full: $full)
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.25), value: full)
    .onAppear { if isDone && summaryAt == 0 { summaryAt = nowMs() } }
    .onChange(of: isDone) { _, done in if done { summaryAt = nowMs() } }
    .task(id: phase == nil) {
      guard phase == nil else { return }
      try? await Task.sleep(nanoseconds: 700_000_000)
      if mac.finished == nil && !mac.alarmActive { store.closeAlarm() }
    }
  }

  // MARK: Timeline

  private var events: [EventItem] {
    let from = (mac.state.at ?? 0) - 2000
    let mine = mac.state.events.filter { $0.t >= from }
    let list = mine.isEmpty ? mac.state.events : mine
    return list.enumerated().sorted { a, b in a.element.t != b.element.t ? a.element.t > b.element.t : a.offset > b.offset }.map(\.element)
  }

  private var timeline: some View {
    ScrollView {
      EventList(events: events, mac: mac)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
    .frame(maxHeight: .infinity)
  }

  // MARK: Save photos and the evidence pack

  private var secondary: some View {
    HStack(spacing: 6) {
      SecondaryButton(symbol: "square.and.arrow.down", title: t("sec_save")) {
        Task { await store.savePhotos(of: mac, photos: photos.sorted()) }
      }
      SecondaryButton(symbol: "doc.text", title: t("sec_ev")) { store.sheet = .evidence(mac: mac.id, record: nil) }
    }
    .padding(.horizontal, 14)
    .padding(.top, 6)
  }

  // MARK: The two big buttons

  private var actions: some View {
    let quiet = isTest || phase == .returned || phase == .muted
    return HStack(spacing: 10) {
      if quiet {
        Button {} label: { bigLabel(t("ab_silent"), "speaker.slash.fill") }
          .buttonStyle(AlarmButtonStyle(kind: .stop))
          .disabled(true)
      } else {
        Button { Task { await store.hush(mac) } } label: {
          bigLabel(t(phase == .warn ? "ab_hushWarn" : "ab_stop"), "speaker.slash.fill")
        }
        .buttonStyle(AlarmButtonStyle(kind: .stop))
      }
      Button { Task { await store.disarm(mac) } } label: {
        bigLabel(t("ab_dis"), store.faceRequired ? "faceid" : nil)
      }
      .buttonStyle(AlarmButtonStyle(kind: .disarm))
    }
    .padding(.horizontal, 14)
    .padding(.top, 8)
    .padding(.bottom, 10)
  }

  private func bigLabel(_ text: String, _ symbol: String?) -> some View {
    HStack(spacing: 8) {
      if let symbol { Image(systemName: symbol).font(.system(size: 20, weight: .semibold)) }
      Text(text).lineLimit(1).minimumScaleFactor(0.75)
    }
  }
}

struct AlarmButtonStyle: ButtonStyle {
  enum Kind { case stop, disarm }
  var kind: Kind
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 18, weight: .heavy))
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity)
      .frame(height: 62)
      .background(background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .strokeBorder(kind == .disarm ? Theme.rim : Color.clear, lineWidth: 1)
      )
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
  }

  private var foreground: Color {
    switch kind {
    case .stop: return enabled ? Theme.bg : Theme.ink3
    case .disarm: return Theme.ink
    }
  }

  private var background: Color {
    switch kind {
    case .stop: return enabled ? Theme.ink : Theme.cardHi
    case .disarm: return Theme.cardHi
    }
  }
}

struct SecondaryButton: View {
  var symbol: String
  var title: String
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(Theme.ink)
          .frame(width: 40, height: 40)
          .background(Theme.cardHi, in: Circle())
        Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink2).lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 8)
      .padding(.bottom, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(PressableStyle())
  }
}

// MARK: - Header

struct AlarmHeader: View {
  var mac: MacModel
  var phase: AlarmPhase?
  var headline: String
  var test: Bool
  var done: Bool
  var finished: FinishedAlarm?
  var offline: Bool
  var close: () -> Void

  private var colors: [Color] {
    switch phase {
    case .warn: return [Color(hex: 0xff8a3d), Color(hex: 0xe45f17)]
    case .returned, .muted: return [Color(hex: 0x7c1a23), Color(hex: 0x5a0f17)]
    case .done: return [Color(hex: 0x2fbf6e), Color(hex: 0x1d9a55)]
    default: return [Color(hex: 0xff4d55), Color(hex: 0xd5232f)]
    }
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { ctx in
      let now = ctx.date.ms
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
          Button(action: close) {
            Image(systemName: "chevron.down")
              .font(.system(size: 16, weight: .bold))
              .frame(width: 34, height: 34)
              .background(.black.opacity(0.18), in: Circle())
          }
          .accessibilityLabel(t("cancel"))
          HStack(spacing: 6) {
            Text(t(done ? "alTtlDone" : "alTtl")).font(.system(size: 13, weight: .bold)).tracking(0.8).opacity(0.85)
            if test {
              Text(t("testTag")).font(.system(size: 11, weight: .heavy)).tracking(0.6)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
          }
          Spacer(minLength: 0)
          if phase == .warn && !offline { WarnRing(mac: mac, now: now) }
        }
        .frame(height: 36)
        .padding(.bottom, 6)
        Text(headline)
          .font(.system(size: 27, weight: .heavy))
          .lineSpacing(1)
          .fixedSize(horizontal: false, vertical: true)
        Text(meta(now))
          .font(.system(size: 13.5))
          .monospacedDigit()
          .foregroundStyle(.white.opacity(0.86))
          .padding(.top, 6)
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 18)
      .padding(.bottom, 16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background {
      ZStack {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        if (phase == .siren || phase == .warn) && !offline { BeatOverlay() }
      }
      .ignoresSafeArea(edges: .top)
    }
    .animation(.easeInOut(duration: 0.6), value: phase)
  }

  private func meta(_ now: Ms) -> String {
    if let f = finished { return t("alMetaDone", Fmt.hm(f.at) + "–" + Fmt.hm(f.endedAt), mac.name) }
    let at = mac.state.at ?? mac.state.since
    return t("alMeta", Fmt.hm(at), Fmt.elapsed(now - at), mac.name)
  }
}

/// The white flash that pulses with the siren.
struct BeatOverlay: View {
  var body: some View {
    TimelineView(.animation) { ctx in
      let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
      let opacity = p < 0.15 ? 1 : 1 - (p - 0.15) / 0.85
      RadialGradient(colors: [.white.opacity(0.3), .clear], center: .top, startRadius: 0, endRadius: 320)
        .opacity(opacity)
    }
    .allowsHitTesting(false)
  }
}

/// The ring that counts down the voice warning.
struct WarnRing: View {
  var mac: MacModel
  var now: Ms

  var body: some View {
    let s = mac.state
    let total = max(1, (s.softEnd ?? now) - (s.at ?? now))
    let left = Double(max(0, (s.softEnd ?? now) - now)) / Double(total)
    ZStack {
      Circle().stroke(.white.opacity(0.28), lineWidth: 3.4)
      Circle().trim(from: 0, to: left).stroke(.white, style: StrokeStyle(lineWidth: 3.4, lineCap: .round)).rotationEffect(.degrees(-90))
      Text("\(mac.snapshot.secsLeft(until: s.softEnd, now: now))").font(.rounded(16, .bold)).monospacedDigit()
    }
    .frame(width: 40, height: 40)
  }
}

// MARK: - The picture

struct MediaChip: View {
  var symbol: String?
  var text: String
  var spinner = false
  var body: some View {
    HStack(spacing: 5) {
      if spinner { ProgressView().controlSize(.mini).tint(.white) }
      if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
      Text(text).font(.system(size: 11.5, weight: .semibold)).monospacedDigit().lineLimit(1)
    }
    .foregroundStyle(.white.opacity(0.9))
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(.black.opacity(0.5), in: Capsule())
    .background(.ultraThinMaterial, in: Capsule())
  }
}

struct LiveTag: View {
  @State private var on = true
  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(.white).frame(width: 6, height: 6).opacity(on ? 1 : 0.2)
      Text(t("live")).font(.system(size: 11.5, weight: .heavy)).tracking(0.7)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(Theme.red, in: Capsule())
    .onAppear {
      withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { on = false }
    }
  }
}

struct AlarmMedia: View {
  @Environment(AppStore.self) private var store
  var mac: MacModel
  var phase: AlarmPhase?
  var photos: [Ms]
  var hasCamera: Bool
  var offline: Bool
  @Binding var zoom: Bool
  @Binding var full: Bool
  var headline: String
  @State private var page = 0
  @State private var hintGone = false

  var body: some View {
    ZStack {
      Color.black
      if hasCamera { live } else { strip }
    }
    .clipped()
  }

  // MARK: Live

  private var live: some View {
    TimelineView(.periodic(from: .now, by: 1)) { ctx in
      let age = max(0, Int((ctx.date.ms - mac.frameAt) / 1000))
      ZStack {
        if let image = mac.frame {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .scaleEffect(zoom ? 2.2 : 1)
            .saturation(offline ? 0 : 1)
            .brightness(offline ? -0.3 : 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: zoom)
        } else if !offline {
          VStack(spacing: 8) {
            ProgressView().tint(.white)
            Text(t("live")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
          }
        }
        VStack {
          HStack(alignment: .top) {
            if offline {
              EmptyView()
            } else {
              LiveTag()
            }
            Spacer()
            if !offline && mac.frame != nil {
              if age >= 5 {
                MediaChip(symbol: nil, text: t("slow"), spinner: true)
              } else if age >= 2 {
                MediaChip(symbol: nil, text: t("lat", age))
              }
            }
          }
          Spacer()
          HStack(alignment: .bottom) {
            if !zoom && !hintGone && !offline { MediaChip(symbol: nil, text: t("dbl")) }
            Spacer()
            Button { full = true } label: {
              Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel(t("live"))
          }
        }
        .padding(12)
        if offline {
          VStack(spacing: 6) {
            Image(systemName: "wifi.slash").font(.system(size: 20))
            Text(t("offMac")).font(.system(size: 15, weight: .bold))
            Text(t("offFrozen", Fmt.hms(mac.snapshot.lastSeenTime))).font(.system(size: 12)).opacity(0.75)
          }
          .foregroundStyle(.white)
          .padding(.horizontal, 16).padding(.vertical, 12)
          .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
      }
      .contentShape(Rectangle())
      .onTapGesture(count: 2) {
        hintGone = true
        zoom.toggle()
      }
    }
  }

  // MARK: Photos when the camera cannot stream

  private var strip: some View {
    ZStack {
      if photos.isEmpty {
        Text(t(mac.state.health.cam ? "noPhotos" : "noCam")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
          .multilineTextAlignment(.center).padding(.horizontal, 24)
      } else {
        TabView(selection: $page) {
          ForEach(Array(photos.enumerated()), id: \.offset) { i, ms in
            RelayPhoto(mac: mac, ms: ms).tag(i)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        VStack {
          HStack {
            MediaChip(symbol: "photo", text: t("photosTaken"))
            Spacer()
            MediaChip(symbol: nil, text: "\(min(page, photos.count - 1) + 1) / \(photos.count)")
          }
          Spacer()
          if offline {
            HStack {
              MediaChip(symbol: "wifi.slash", text: t("offMac"))
              Spacer()
            }
          }
        }
        .padding(12)
        .allowsHitTesting(false)
      }
    }
  }
}

/// The picture on the whole screen, with the siren button within reach.
struct LiveFullscreen: View {
  @Environment(AppStore.self) private var store
  var mac: MacModel
  var phase: AlarmPhase?
  var headline: String
  @Binding var full: Bool

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if let image = mac.frame {
        Image(uiImage: image).resizable().scaledToFit().ignoresSafeArea()
      } else {
        ProgressView().tint(.white)
      }
      VStack {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 8) {
            LiveTag()
            MediaChip(symbol: nil, text: headline)
          }
          Spacer()
          Button { full = false } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.white)
              .frame(width: 34, height: 34)
              .background(.black.opacity(0.45), in: Circle())
          }
        }
        Spacer()
        if phase == .siren || phase == .warn {
          Button { Task { await store.hush(mac) } } label: {
            HStack(spacing: 8) {
              Image(systemName: "speaker.slash.fill")
              Text(t(phase == .warn ? "ab_hushWarn" : "ab_stop"))
            }
          }
          .buttonStyle(.big(phase == .warn ? .ink : .red))
        }
      }
      .padding(16)
    }
    .preferredColorScheme(.dark)
  }
}

// MARK: - What the alarm says it is

struct AlarmLabel: View {
  var mac: MacModel
  var phase: AlarmPhase?
  var offline: Bool
  var test: Bool

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { ctx in
      if let spec = spec(now: ctx.date.ms) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: spec.symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(spec.fg)
            .frame(width: 40, height: 40)
            .background(spec.bg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
          VStack(alignment: .leading, spacing: 2) {
            Text(spec.title).font(.system(size: 19, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
            Text(spec.sub).font(.system(size: 13.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 2)
      }
    }
  }

  private struct Spec {
    var symbol: String
    var title: String
    var sub: String
    var fg: Color
    var bg: Color
  }

  private func spec(now: Ms) -> Spec? {
    let red = Theme.red.opacity(0.16)
    if offline {
      return Spec(
        symbol: "wifi.slash", title: t("lb_off", Fmt.hm(mac.snapshot.lastSeenTime)), sub: t("lb_offS"), fg: Theme.ink2, bg: Theme.cardHi)
    }
    if test && phase != .warn {
      return Spec(symbol: "testtube.2", title: t("lb_test"), sub: t("lb_testS"), fg: Theme.textRed, bg: red)
    }
    switch phase {
    case .warn:
      let secs = mac.snapshot.secsLeft(until: mac.state.softEnd, now: now)
      return Spec(
        symbol: "hand.raised.fill", title: t("lb_warn", secs), sub: t("lb_warnS"), fg: Theme.textOrange, bg: Theme.orange.opacity(0.16))
    case .siren:
      return Spec(
        symbol: "speaker.wave.3.fill", title: t("lb_siren"), sub: t(mac.state.carried ? "lb_sirenS" : "lb_sirenN"), fg: Theme.textRed,
        bg: red)
    case .returned:
      return Spec(symbol: "arrow.uturn.backward", title: t("lb_returned"), sub: t("lb_returnedS"), fg: Theme.ink, bg: Theme.cardHi)
    case .muted:
      return Spec(
        symbol: "speaker.slash.fill", title: t(mac.snapshot.calledOff ? "lb_calledoff" : "lb_muted"), sub: t("lb_mutedS"), fg: Theme.ink,
        bg: Theme.cardHi)
    default:
      return nil
    }
  }
}

// MARK: - After it ended

struct AlarmSummary: View {
  @Environment(AppStore.self) private var store
  var mac: MacModel
  var finished: FinishedAlarm
  var since: Ms
  var done: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 6) {
        ShieldView(look: .clear, size: 64).frame(width: 64, height: 64)
        Text(t(finished.byKey) + " · " + Fmt.hm(finished.endedAt))
          .font(.system(size: 14)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
      }
      .padding(.top, 6)
      .padding(.bottom, 18)

      VStack(spacing: 0) {
        Text(t("sumT")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
          .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
        SummaryRow(key: "sum_trig", value: finished.trigger.title)
        Hairline(inset: 16)
        SummaryRow(key: "sum_start", value: Fmt.hms(finished.at))
        Hairline(inset: 16)
        SummaryRow(
          key: "sum_siren",
          value: finished.test ? t("lb_test") : finished.sirenMs > 0 ? Fmt.secs(max(1, Int((Double(finished.sirenMs) / 1000).rounded()))) : t("none"))
        Hairline(inset: 16)
        SummaryRow(key: "sum_photos", value: t("photosN", finished.photos.count))
        Hairline(inset: 16)
        SummaryRow(key: "sum_video", value: t("sum_videoF"))
      }
      .brbCard(radius: 22)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

      if !finished.photos.isEmpty {
        Button { Task { await store.savePhotos(of: mac, photos: finished.photos) } } label: {
          HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
            Text(t("sec_save"))
          }
        }
        .buttonStyle(.big(.glass, height: 46, size: 15.5))
        .padding(.top, 14)
      }

      Spacer(minLength: 12)

      TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
        let wait = Int((Double(since + 3000 - ctx.date.ms) / 1000).rounded(.up))
        Button(action: done) { Text(wait > 0 && since > 0 ? t("doneWait", wait) : t("doneBtn")) }
          .buttonStyle(.big(.ink))
          .disabled(wait > 0 && since > 0)
      }
    }
    .padding(.horizontal, 18)
    .padding(.top, 18)
    .padding(.bottom, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
  }
}

struct SummaryRow: View {
  var key: String
  var value: String
  var body: some View {
    HStack {
      Text(t(key)).font(.system(size: 15.5, weight: .medium))
      Spacer(minLength: 8)
      Text(value).font(.system(size: 15)).monospacedDigit().multilineTextAlignment(.trailing)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 11)
  }
}

/// "TEST" over everything, faint, so nobody mistakes a drill for a theft.
struct TestWatermark: View {
  var body: some View {
    GeometryReader { geo in
      let word = String(repeating: t("testTag") + "   ", count: 14)
      VStack(spacing: 30) {
        ForEach(0..<14, id: \.self) { _ in
          Text(word).font(.system(size: 30, weight: .black)).tracking(3).lineLimit(1).fixedSize()
        }
      }
      .frame(width: geo.size.width * 2, height: geo.size.height * 2)
      .rotationEffect(.degrees(-24))
      .position(x: geo.size.width / 2, y: geo.size.height / 2)
      .foregroundStyle(Theme.ink)
      .opacity(0.07)
    }
    .clipped()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
