import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// First run, and "Pair a new Mac": welcome cards, the two permissions, the QR code or the six digits, a name,
/// a test alert. Covers the whole screen.
struct OnboardingView: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    ZStack {
      Backdrop()
      if let o = store.onboarding {
        step(o)
          .id(o.step)
          .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.3), value: store.onboarding?.step)
  }

  @ViewBuilder private func step(_ o: Onboarding) -> some View {
    switch o.step {
    case .welcome: WelcomeStep(page: o.page, replay: o.replay)
    case .notif, .notifoff: PermissionStep(kind: .notif)
    case .crit: PermissionStep(kind: .crit)
    case .scan, .camdenied, .expired, .macoffline: ScanStep(o: o)
    case .code: CodeStep(o: o)
    case .paired: PairedStep(o: o)
    case .done: DoneStep()
    case .nomac: NoMacStep(o: o)
    }
  }
}

// MARK: - Welcome

struct WelcomeStep: View {
  @Environment(AppStore.self) private var store
  var page: Int
  var replay: Bool

  private let cards: [(String, String)] = [("w1T", "w1P"), ("w2T", "w2P"), ("w3T", "w3P")]

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        Button(t("skip")) { skip() }
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Theme.ink2)
          .padding(.horizontal, 8)
          .frame(height: 36)
      }
      .padding(.horizontal, 12)
      TabView(selection: Binding(get: { store.onboarding?.page ?? 0 }, set: { store.onboarding?.page = $0 })) {
        ForEach(0..<3, id: \.self) { i in
          VStack(spacing: 10) {
            Spacer(minLength: 0)
            illustration(i).frame(height: 180)
            Text(t(cards[i].0)).font(.system(size: 26, weight: .bold)).multilineTextAlignment(.center).padding(.top, 22)
            Text(t(cards[i].1)).font(.system(size: 16)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 30)
          .tag(i)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      HStack(spacing: 7) {
        ForEach(0..<3, id: \.self) { i in
          Capsule().fill(i == page ? Theme.ink : Theme.ink.opacity(0.2)).frame(width: i == page ? 20 : 7, height: 7)
        }
      }
      .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
      .padding(.bottom, 18)
      Button { store.onboardingNext() } label: { Text(t(page < 2 ? "continue" : "w_start")) }
        .buttonStyle(.big(.ink))
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
  }

  private func skip() {
    if replay { store.finishOnboarding() } else { store.onboarding?.step = .notif }
  }

  @ViewBuilder private func illustration(_ i: Int) -> some View {
    switch i {
    case 0: IllFrost()
    case 1: IllCam()
    default: IllStop()
    }
  }
}

/// The screen frosts over and asks people not to touch.
struct IllFrost: View {
  var body: some View {
    VStack(spacing: 0) {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(LinearGradient(colors: [Color(hex: 0x3a4a78), Color(hex: 0x1b2440)], startPoint: .top, endPoint: .bottom))
        .frame(width: 196, height: 124)
        .overlay {
          VStack(spacing: 8) {
            ShieldView(look: .armed, size: 42)
            Text(t("ill_dont")).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.ultraThinMaterial.opacity(0.6))
          .background(Color.white.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
          .padding(8)
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1.5))
      Capsule().fill(Theme.cardHi).frame(width: 224, height: 8).padding(.top, 4)
    }
  }
}

/// The camera keeps the last ten seconds, in memory.
struct IllCam: View {
  var body: some View {
    ZStack {
      Circle().stroke(Theme.hair, lineWidth: 6)
      Circle().trim(from: 0, to: 0.72).stroke(Theme.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
      Circle()
        .fill(RadialGradient(colors: [Color(hex: 0x3a4a78), Color(hex: 0x0b0f1c)], center: .init(x: 0.35, y: 0.3), startRadius: 2, endRadius: 40))
        .frame(width: 70, height: 70)
        .overlay(Circle().strokeBorder(Theme.rim, lineWidth: 2))
      Text("10 s").font(.rounded(15, .bold)).foregroundStyle(Theme.tint).offset(y: 62)
    }
    .frame(width: 150, height: 150)
  }
}

/// A finger on Touch ID, or the phone's two buttons.
struct IllStop: View {
  var body: some View {
    HStack(spacing: 22) {
      Image(systemName: "touchid")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(Theme.tint)
        .frame(width: 84, height: 84)
        .background(Theme.tintBg, in: Circle())
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Theme.bg)
        .frame(width: 80, height: 140)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.tint, lineWidth: 2))
        .overlay {
          VStack(spacing: 8) {
            Capsule().fill(Theme.ink).frame(height: 22)
            Capsule().fill(Theme.cardHi).overlay(Capsule().strokeBorder(Theme.rim)).frame(height: 22)
          }
          .padding(.horizontal, 10)
        }
    }
  }
}

// MARK: - Notifications

struct PermissionStep: View {
  enum Kind { case notif, crit }
  @Environment(AppStore.self) private var store
  var kind: Kind

  private var isNotif: Bool { kind == .notif }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        RoundIconButton(symbol: "chevron.left", label: t("cancel")) { back() }
        Spacer()
      }
      .padding(.horizontal, 16)
      Spacer(minLength: 0)
      VStack(spacing: 0) {
        mock.padding(.bottom, 28)
        Text(t(isNotif ? "nT" : "cT")).font(.system(size: 26, weight: .bold)).multilineTextAlignment(.center)
        Text(t(isNotif ? "nP" : "cP")).font(.system(size: 16)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
          .padding(.top, 10)
      }
      .padding(.horizontal, 30)
      Spacer(minLength: 0)
      VStack(spacing: 6) {
        Button { primary() } label: {
          Text(isNotif && store.notif == .denied ? t("camBtn") : t(isNotif ? "nBtn" : "cBtn"))
        }
        .buttonStyle(.big(.ink))
        Button(t("later")) { later() }
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(Theme.ink2)
          .frame(height: 44)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 12)
    }
  }

  private var mock: some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 14) {
        Text(Fmt.hm(nowMs())).font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(Theme.ink2)
        HStack(spacing: 10) {
          AppMark(size: 38)
          VStack(alignment: .leading, spacing: 1) {
            Text((isNotif ? "" : t("lvl_crit") + " · ") + t("p_alarm_lift")).font(.system(size: 14, weight: .semibold))
            Text(store.macs.first?.name ?? "MacBook").font(.system(size: 13)).foregroundStyle(Theme.ink2)
          }
          Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
      }
      .padding(18)
      .frame(width: 280)
      .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      Image(systemName: isNotif ? "bell.fill" : "speaker.wave.3.fill")
        .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
        .frame(width: 42, height: 42).background(Theme.red, in: Circle())
        .offset(x: 12, y: -14)
    }
  }

  private func back() {
    if isNotif {
      store.onboarding?.step = .welcome
      store.onboarding?.page = 2
    } else {
      store.onboarding?.step = .notif
    }
  }

  private func primary() {
    Task { if isNotif { await store.allowNotifications() } else { await store.allowCritical() } }
  }

  private func later() {
    if isNotif { store.skipNotifications() } else { store.skipCritical() }
  }
}

// MARK: - Scan

struct ScanStep: View {
  @Environment(AppStore.self) private var store
  var o: Onboarding

  private var scanning: Bool { o.step == .scan && o.phase == .scanning }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()
      if store.isDemo || o.step == .camdenied {
        FauxMacScene()
      } else {
        QRScannerView(active: scanning, onCode: found, onDenied: { store.onboarding?.step = .camdenied })
          .ignoresSafeArea()
      }
      Color.black.opacity(o.step == .expired ? 0.45 : 0.18).ignoresSafeArea()
      Viewfinder(locked: o.phase == .pairing, dimmed: o.step == .expired)

      VStack(spacing: 0) {
        HStack {
          Button { store.finishOnboarding() } label: {
            Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
              .frame(width: 36, height: 36).background(.black.opacity(0.45), in: Circle())
          }
          .accessibilityLabel(t("cancel"))
          Spacer()
        }
        .padding(.horizontal, 16)
        VStack(spacing: 6) {
          Text(t("scanT")).font(.system(size: 22, weight: .bold))
          HStack(spacing: 4) {
            Text(t("scHint1"))
            ShieldView(look: .idle, size: 15, mono: true)
            Text(t("scHint2"))
          }
          .font(.system(size: 13.5))
          .opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
        Spacer()
        bottom.padding(.horizontal, 16).padding(.bottom, 12)
      }

      if o.step == .camdenied { cameraDenied }
    }
    .preferredColorScheme(.dark)
  }

  private func found(_ text: String) {
    guard scanning, let code = PairingCode.parse(text) else { return }
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    Task { await store.claim(code) }
  }

  @ViewBuilder private var bottom: some View {
    switch o.step {
    case .expired:
      ScanCard(symbol: "qrcode", title: t("expT"), message: t("expP"), button: (t("expBtn"), "arrow.clockwise")) { store.rescan() }
    case .macoffline:
      ScanCard(symbol: "wifi.slash", title: t("moT"), message: t("moP"), button: (t("moBtn"), "arrow.clockwise")) { store.rescan() }
    default:
      if o.phase == .pairing {
        HStack(spacing: 10) {
          ProgressView().tint(.white)
          Text(t("pairing")).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity).frame(height: 56)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      } else {
        VStack(spacing: 10) {
          Button { store.onboarding?.step = .code } label: {
            HStack(spacing: 8) {
              Image(systemName: "number.square")
              Text(t("scCode"))
            }
          }
          .buttonStyle(.big(.glass))
          Button(t("scNoMac")) {
            store.onboarding?.cameFrom = .scan
            store.onboarding?.step = .nomac
          }
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(.white.opacity(0.85))
          .frame(height: 40)
        }
      }
    }
  }

  private var cameraDenied: some View {
    VStack(spacing: 10) {
      Image(systemName: "camera.fill").font(.system(size: 26)).foregroundStyle(.white)
        .frame(width: 64, height: 64).background(.white.opacity(0.14), in: Circle())
        .overlay { Image(systemName: "slash.circle").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(.white.opacity(0.6)) }
      Text(t("camT")).font(.system(size: 21, weight: .bold)).foregroundStyle(.white).multilineTextAlignment(.center).padding(.top, 6)
      Text(t("camP")).font(.system(size: 15)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center)
      Button { store.openAppSettings() } label: { Text(t("camBtn")) }
        .buttonStyle(.big(.tint))
        .padding(.top, 10)
      Button(t("camAlt")) { store.onboarding?.step = .code }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white.opacity(0.75))
        .frame(height: 40)
    }
    .padding(.horizontal, 30)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black.opacity(0.82).ignoresSafeArea())
  }
}

struct ScanCard: View {
  var symbol: String
  var title: String
  var message: String
  var button: (String, String)
  var action: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(.white)
          .frame(width: 40, height: 40).background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.system(size: 16, weight: .semibold))
          Text(message).font(.system(size: 13.5)).opacity(0.75).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }
      Button(action: action) {
        HStack(spacing: 8) {
          Image(systemName: button.1)
          Text(button.0)
        }
      }
      .buttonStyle(.big(.tint))
    }
    .foregroundStyle(.white)
    .padding(16)
    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }
}

/// The four corners to line the code up in.
struct Viewfinder: View {
  var locked: Bool
  var dimmed: Bool

  private static let alignments: [Alignment] = [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading]

  var body: some View {
    let color: Color = locked ? Theme.green : .white.opacity(dimmed ? 0.35 : 0.9)
    ZStack {
      ForEach(0..<4, id: \.self) { i in
        Corner()
          .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
          .frame(width: 34, height: 34)
          .rotationEffect(.degrees(Double(i) * 90))
          .frame(width: 250, height: 250, alignment: Viewfinder.alignments[i])
      }
    }
    .frame(width: 250, height: 250)
    .animation(.easeInOut(duration: 0.25), value: locked)
  }

  struct Corner: Shape {
    func path(in rect: CGRect) -> Path {
      var p = Path()
      p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
      p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 10))
      p.addQuadCurve(to: CGPoint(x: rect.minX + 10, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
      p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      return p
    }
  }
}

/// With no camera (the demo, the simulator) a Mac's screen with its code stands in for the view.
struct FauxMacScene: View {
  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(hex: 0x1b2440), Color(hex: 0x05070d)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
      VStack(spacing: 6) {
        VStack(spacing: 6) {
          if let image = FauxMacScene.qr() {
            Image(uiImage: image).interpolation(.none).resizable().frame(width: 160, height: 160)
          }
          Text(t("macQR")).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: 0x0b0f1c))
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
    }
  }

  static func qr() -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data("brb://pair?c=demodemo0".utf8)
    guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
      let cg = CIContext().createCGImage(output, from: output.extent)
    else { return nil }
    return UIImage(cgImage: cg)
  }
}

// MARK: - Six digits

struct CodeStep: View {
  @Environment(AppStore.self) private var store
  var o: Onboarding

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        RoundIconButton(symbol: "chevron.left", label: t("cancel")) { store.rescan() }
        Spacer()
      }
      .padding(.horizontal, 16)
      VStack(alignment: .leading, spacing: 8) {
        Text(t("codeT")).font(.system(size: 26, weight: .bold))
        Text(t("codeP")).font(.system(size: 15.5)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 28)
      .padding(.top, 8)

      HStack(spacing: 10) {
        ForEach(0..<6, id: \.self) { i in
          let digits = Array(o.code)
          Text(i < digits.count ? String(digits[i]) : "")
            .font(.rounded(30, .semibold))
            .frame(width: 46, height: 58)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(o.codeError ? Theme.red : (i == digits.count && o.phase != .pairing ? Theme.tint : Color.clear), lineWidth: 2))
        }
      }
      .padding(.top, 30)
      Group {
        if o.phase == .pairing {
          HStack(spacing: 8) {
            ProgressView()
            Text(t("pairing")).font(.system(size: 14)).foregroundStyle(Theme.ink2)
          }
        } else if o.codeError {
          Text(t("err_code")).font(.system(size: 14)).foregroundStyle(Theme.textRed).multilineTextAlignment(.center)
        } else {
          Text(" ").font(.system(size: 14))
        }
      }
      .frame(height: 24)
      .padding(.top, 12)
      Spacer(minLength: 0)
      keypad.padding(.horizontal, 28).padding(.bottom, 14)
    }
  }

  private var keypad: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
      ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "del"], id: \.self) { key in
        if key.isEmpty {
          Color.clear.frame(height: 60)
        } else {
          Button { tap(key) } label: {
            Group {
              if key == "del" {
                Image(systemName: "delete.left").font(.system(size: 20, weight: .medium))
              } else {
                Text(key).font(.rounded(26, .medium))
              }
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(key == "del" ? Color.clear : Theme.cardHi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }
          .buttonStyle(PressableStyle())
          .disabled(o.phase == .pairing)
        }
      }
    }
  }

  private func tap(_ key: String) {
    guard var o = store.onboarding else { return }
    o.codeError = false
    if key == "del" {
      o.code = String(o.code.dropLast())
      store.onboarding = o
      return
    }
    guard o.code.count < 6 else { return }
    o.code += key
    store.onboarding = o
    if o.code.count == 6, let parsed = PairingCode.parse(o.code) {
      Task { await store.claim(parsed) }
    }
  }
}

// MARK: - Paired

struct PairedStep: View {
  @Environment(AppStore.self) private var store
  var o: Onboarding
  @State private var name = ""
  @FocusState private var focused: Bool

  private var mac: MacModel? { store.mac(o.pairedID) }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 0) {
          ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
              RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1.5))
                .overlay { ShieldView(look: .armed, size: 40) }
                .frame(width: 130, height: 84)
              Capsule().fill(Theme.cardHi).frame(width: 156, height: 7).padding(.top, 4)
            }
            Image(systemName: "checkmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
              .frame(width: 32, height: 32).background(Theme.green, in: Circle())
              .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 3))
              .offset(x: 10, y: 10)
          }
          .padding(.top, 36)
          Text(t("pdT")).font(.system(size: 26, weight: .bold)).padding(.top, 26)
          Text(mac?.model ?? "").font(.system(size: 15.5)).foregroundStyle(Theme.ink2).padding(.top, 4)

          HStack(spacing: 8) {
            TextField("", text: $name)
              .focused($focused)
              .font(.system(size: 17, weight: .medium))
              .multilineTextAlignment(.center)
              .submitLabel(.done)
              .onSubmit { focused = false }
            Image(systemName: "pencil").foregroundStyle(Theme.ink3)
          }
          .padding(.horizontal, 16).frame(height: 50)
          .background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          .padding(.horizontal, 28)
          .padding(.top, 22)

          Button { store.sendTestPush() } label: { testRow }
            .buttonStyle(PressableStyle())
            .disabled(o.testState != .idle)
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
      }
      Button { next() } label: { Text(t("continue")) }
        .buttonStyle(.big(.ink))
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
    .onAppear { name = mac?.name ?? "" }
  }

  private var testRow: some View {
    HStack(spacing: 12) {
      Image(systemName: "bell.fill").foregroundStyle(Theme.tint)
        .frame(width: 38, height: 38).background(Theme.tintBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      VStack(alignment: .leading, spacing: 1) {
        Text(t("testT")).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Theme.ink)
        Text(t("testS")).font(.system(size: 12.5)).foregroundStyle(Theme.ink2).multilineTextAlignment(.leading)
      }
      Spacer(minLength: 6)
      switch o.testState {
      case .idle: Text(t("testSend")).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.tint)
      case .sending: ProgressView()
      case .got:
        HStack(spacing: 4) {
          Image(systemName: "checkmark")
          Text(t("testGot"))
        }
        .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textGreen)
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .brbCard(radius: 18)
  }

  private func next() {
    if let mac {
      let clean = name.trimmingCharacters(in: .whitespaces)
      if !clean.isEmpty && clean != mac.name {
        mac.rename(clean)
        store.persist()
      }
    }
    if o.extra { store.finishOnboarding() } else { store.onboarding?.step = .done }
  }
}

// MARK: - Done

struct DoneStep: View {
  @Environment(AppStore.self) private var store
  @State private var popped = false

  var body: some View {
    VStack(spacing: 0) {
      Spacer()
      ShieldView(look: .armed, size: 120)
        .scaleEffect(popped ? 1 : 0.4)
        .opacity(popped ? 1 : 0)
      Text(t("dnT")).font(.system(size: 26, weight: .bold)).padding(.top, 24)
      Text(t("dnP")).font(.system(size: 16)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center).padding(.horizontal, 36).padding(.top, 10)
      Spacer()
      Button { store.finishOnboarding() } label: { Text(t("dnBtn")) }
        .buttonStyle(.big(.ink))
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
    .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { popped = true } }
  }
}

// MARK: - No Mac yet

struct NoMacStep: View {
  @Environment(AppStore.self) private var store
  var o: Onboarding

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        RoundIconButton(symbol: "chevron.left", label: t("cancel")) { back() }
        Spacer()
      }
      .padding(.horizontal, 16)
      ScrollView {
        VStack(spacing: 0) {
          VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card)
              .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1.5))
              .overlay { Image(systemName: "arrow.down.circle.fill").font(.system(size: 32)).foregroundStyle(Theme.tint) }
              .frame(width: 130, height: 84)
            Capsule().fill(Theme.cardHi).frame(width: 156, height: 7).padding(.top, 4)
          }
          .padding(.top, 8)
          Text(t("nmT")).font(.system(size: 24, weight: .bold)).multilineTextAlignment(.center).padding(.top, 22)
          Text(t("nmP")).font(.system(size: 15.5)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center).padding(.top, 8)
          LinkOptions().padding(.top, 20)
        }
        .padding(.horizontal, 24)
      }
      VStack(spacing: 4) {
        Button(t("nm_done")) { store.rescan() }
          .font(.system(size: 15.5, weight: .semibold))
          .foregroundStyle(Theme.tint)
          .frame(height: 40)
        Button(t("tryDemo")) { store.enterDemo() }
          .font(.system(size: 14))
          .foregroundStyle(Theme.ink3)
          .frame(height: 36)
      }
      .padding(.bottom, 12)
    }
  }

  private func back() {
    store.onboarding?.step = o.cameFrom
  }
}
