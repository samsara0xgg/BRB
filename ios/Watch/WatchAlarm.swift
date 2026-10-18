import SwiftUI
import UIKit

// MARK: - Alarm

/// The alarm page: what happened, the picture, and the one button that matters. The Watch cannot disarm, so
/// it says to do that on the iPhone.
struct WAlarmView: View {
  @ObservedObject var model: WatchModel
  let id: String
  @State private var beat = false
  @State private var zoom = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let snap = model.snapshot(for: id)
    let phase = snap.alarmPhase ?? AlarmPhase.siren
    ZStack {
      WAlarmBackdrop(phase: phase)
      RadialGradient(
        colors: [washColor(phase).opacity(0.5), Color.clear], center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: 130
      )
      .ignoresSafeArea()
      .opacity(pulses(phase) ? (beat ? 1 : 0.2) : 0)
      .animation(pulse, value: beat)
      .allowsHitTesting(false)

      TimelineView(.periodic(from: Date(), by: 1)) { ctx in
        page(snap: snap, phase: phase, date: ctx.date)
      }
    }
    .onAppear { beat = true }
    .sheet(isPresented: $zoom) {
      WPictureSheet(model: model, id: id)
    }
  }

  private var pulse: Animation? {
    if reduceMotion { return nil }
    return Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true)
  }

  private func pulses(_ phase: AlarmPhase) -> Bool { phase == .siren || phase == .warn }

  private func washColor(_ phase: AlarmPhase) -> Color { phase == .warn ? Theme.orange : Theme.red }

  // MARK: content

  private func page(snap: MacSnapshot, phase: AlarmPhase, date: Date) -> some View {
    let now = date.ms
    let picture = currentPicture(date: date, online: snap.online)
    return GeometryReader { geo in
      let small = geo.size.height < 178
      VStack(spacing: small ? 4 : 6) {
        if model.macs.count > 1 && !small {
          Text(snap.name)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.7))
            .lineLimit(1)
        }
        HStack(alignment: .top, spacing: 8) {
          Button {
            zoom = true
          } label: {
            WAlarmPicture(image: picture.image, live: picture.live, offline: !snap.online)
          }
          .buttonStyle(.plain)
          .disabled(picture.image == nil)
          VStack(alignment: .leading, spacing: 2) {
            Text(heading(snap, phase))
              .font(.system(size: 16, weight: .heavy))
              .foregroundStyle(Color.white)
              .lineLimit(2)
              .minimumScaleFactor(0.8)
            Text(detail(snap, phase, now: now))
              .font(.system(size: 12))
              .foregroundStyle(Color.white.opacity(0.78))
              .lineLimit(3)
              .minimumScaleFactor(0.85)
          }
          Spacer(minLength: 0)
        }
        Spacer(minLength: 0)
        action(snap, phase)
        HStack(spacing: 4) {
          Image(systemName: "iphone")
          Text(t("wv_open"))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.6))
      }
      .padding(.horizontal, 4)
      .frame(width: geo.size.width, height: geo.size.height)
    }
  }

  /// A live frame while the Mac is still streaming one, else the newest photo of this alarm.
  private func currentPicture(date: Date, online: Bool) -> (image: UIImage?, live: Bool) {
    if online, let frame = model.frames[id], date.timeIntervalSince(frame.at) < 8 {
      return (frame.image, true)
    }
    return (model.photos[id]?.image, false)
  }

  private func heading(_ snap: MacSnapshot, _ phase: AlarmPhase) -> String {
    switch phase {
    case .returned: return t("sub_returned")
    case .muted: return t(snap.calledOff ? "sub_calledoff" : "sub_muted")
    default: return (snap.state.test ? t("alTestPre") : "") + snap.title()
    }
  }

  private func detail(_ snap: MacSnapshot, _ phase: AlarmPhase, now: Ms) -> String {
    if !snap.online { return snap.subtitle(now: now) }
    switch phase {
    case .returned: return t("wv_backS")
    case .muted: return t("wv_hushedS")
    default: return snap.subtitle(now: now)
    }
  }

  @ViewBuilder
  private func action(_ snap: MacSnapshot, _ phase: AlarmPhase) -> some View {
    if phase == .siren && !snap.state.test {
      Button {
        Task { await model.send(.hush, to: id) }
      } label: {
        WLabel(symbol: "speaker.slash.fill", text: t("ab_stop"))
      }
      .buttonStyle(WPillStyle.red)
      .disabled(model.busy.contains(id))
    } else if phase == .warn && !snap.state.test {
      Button {
        Task { await model.send(.hush, to: id) }
      } label: {
        WLabel(symbol: "speaker.slash.fill", text: t("ab_hushWarn"))
      }
      .buttonStyle(WPillStyle.orange)
      .disabled(model.busy.contains(id))
    }
  }
}

/// The red (or orange, or dark red) wash behind the alarm.
struct WAlarmBackdrop: View {
  let phase: AlarmPhase

  var body: some View {
    ZStack {
      Color.black
      RadialGradient(
        colors: [top, Color.black], center: UnitPoint(x: 0.5, y: 0), startRadius: 0, endRadius: 210)
    }
    .ignoresSafeArea()
  }

  private var top: Color {
    switch phase {
    case .warn: return Color(hex: 0x7a3a0a)
    case .returned, .muted: return Color(hex: 0x3a0b10)
    default: return Color(hex: 0x7a0f18)
    }
  }
}

/// A small picture of whoever is at the Mac. A red dot says it is live.
struct WAlarmPicture: View {
  let image: UIImage?
  let live: Bool
  let offline: Bool

  var body: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(white: 1, opacity: 0.1))
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .saturation(offline ? 0 : 1)
          .brightness(offline ? -0.3 : 0)
          .frame(width: 72, height: 54)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      } else {
        Image(systemName: "camera.fill")
          .font(.system(size: 18))
          .foregroundStyle(Color.white.opacity(0.4))
          .frame(width: 72, height: 54)
      }
      if live && image != nil {
        Circle()
          .fill(Theme.red)
          .frame(width: 8, height: 8)
          .overlay(Circle().stroke(Color.white, lineWidth: 1))
          .padding(5)
          .accessibilityLabel(t("live"))
      }
    }
    .frame(width: 72, height: 54)
    .accessibilityLabel(t("ww_photoA11y"))
  }
}

/// The picture at full width, for when the small one is tapped.
struct WPictureSheet: View {
  @ObservedObject var model: WatchModel
  let id: String

  var body: some View {
    let image = model.frames[id]?.image ?? model.photos[id]?.image
    ZStack {
      Color.black.ignoresSafeArea()
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
      }
    }
  }
}

// MARK: - Clear

/// The alarm just ended: the green shield, who ended it and when.
struct WDoneView: View {
  let done: WFinished

  var body: some View {
    ZStack {
      RadialGradient(
        colors: [Color(hex: 0x0d4a2a), Color.black], center: UnitPoint(x: 0.5, y: 0.1), startRadius: 0, endRadius: 190
      )
      .ignoresSafeArea()
      VStack(spacing: 6) {
        ShieldView(look: .clear, size: 62)
        Text(t("alH_done"))
          .font(.system(size: 17, weight: .heavy))
          .foregroundStyle(Theme.textGreen)
        Text(t(done.byKey) + " · " + Fmt.hm(done.endedAt))
          .font(.system(size: 12))
          .foregroundStyle(Color.white.opacity(0.74))
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 6)
    }
  }
}
