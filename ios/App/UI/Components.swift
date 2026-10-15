import SwiftUI

// MARK: - Surfaces

extension View {
  /// The rounded card every screen is made of.
  func brbCard(radius: CGFloat = 20) -> some View {
    background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.cardBorder, lineWidth: 1))
      .shadow(color: Color(hex: 0x141e3c, opacity: 0.06), radius: 1, y: 1)
  }

  func screenBackground() -> some View { background(Backdrop()) }
}

// MARK: - Buttons

enum BigButtonKind { case amber, tint, glass, ink, red }

/// The full-width pill buttons: amber for "Start guarding", glass for the quiet ones, red for the alarm.
struct BigButtonStyle: ButtonStyle {
  var kind: BigButtonKind = .amber
  var height: CGFloat = 52
  var size: CGFloat = 17
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: size, weight: .semibold))
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .background(background, in: Capsule())
      .overlay(Capsule().strokeBorder(kind == .glass ? Theme.rim : .clear, lineWidth: 1))
      .shadow(color: shadow, radius: 13, y: 8)
      .opacity(enabled ? 1 : 0.45)
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
  }

  private var foreground: Color {
    switch kind {
    case .amber: return Theme.amberInk
    case .tint: return Color(hex: 0xffffff)
    case .glass: return Theme.ink
    case .ink: return Theme.bg
    case .red: return .white
    }
  }

  private var background: AnyShapeStyle {
    switch kind {
    case .amber: return AnyShapeStyle(LinearGradient(colors: [Theme.amberHi, Theme.amberDeep], startPoint: .top, endPoint: .bottom))
    case .tint: return AnyShapeStyle(Theme.tint)
    case .glass: return AnyShapeStyle(Theme.cardHi)
    case .ink: return AnyShapeStyle(Theme.ink)
    case .red: return AnyShapeStyle(Theme.red)
    }
  }

  private var shadow: Color {
    switch kind {
    case .amber: return Color(hex: 0xdc8c14, opacity: 0.38)
    case .red: return Theme.red.opacity(0.4)
    default: return .clear
    }
  }
}

extension ButtonStyle where Self == BigButtonStyle {
  static func big(_ kind: BigButtonKind = .amber, height: CGFloat = 52, size: CGFloat = 17) -> BigButtonStyle {
    BigButtonStyle(kind: kind, height: height, size: size)
  }
}

struct PressableStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.985 : 1)
      .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
  }
}

/// The small round button in a title row (plus, more).
struct RoundIconButton: View {
  var symbol: String
  var label: String
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.ink)
        .frame(width: 36, height: 36)
        .background(Theme.cardHi, in: Circle())
    }
    .buttonStyle(PressableStyle())
    .accessibilityLabel(label)
  }
}

// MARK: - Chips and labels

struct Chip: View {
  var symbol: String?
  var text: String
  var body: some View {
    HStack(spacing: 5) {
      if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
      Text(text).font(.system(size: 12.5, weight: .medium))
    }
    .foregroundStyle(Theme.ink2)
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Theme.cardHi, in: Capsule())
    .fixedSize()
  }
}

struct SectionHeader: View {
  var text: String
  var trailing: (title: String, action: () -> Void)?
  var body: some View {
    HStack {
      Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
      Spacer()
      if let trailing {
        Button(trailing.title, action: trailing.action).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.tint)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 22)
    .padding(.bottom, 7)
  }
}

struct SectionFooter: View {
  var text: String
  var body: some View {
    Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).padding(.horizontal, 16).padding(.top, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Grouped rows

/// A rounded group of rows with hairlines between them.
struct Grp<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(spacing: 0) { content }
      .frame(maxWidth: .infinity)
      .brbCard(radius: 20)
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

struct Hairline: View {
  var inset: CGFloat = 56
  var body: some View { Rectangle().fill(Theme.hair).frame(height: 1).padding(.leading, inset) }
}

/// The colored tile in front of a settings row.
struct RowIcon: View {
  var symbol: String
  var color: Color = Theme.gray
  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 30, height: 30)
      .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}

struct Row<Trailing: View>: View {
  var icon: (symbol: String, color: Color)?
  var title: String
  var subtitle: String?
  var destructive = false
  var chevron = false
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 12) {
      if let icon { RowIcon(symbol: icon.symbol, color: icon.color) }
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 15.5, weight: .medium)).foregroundStyle(destructive ? Theme.textRed : Theme.ink)
        if let subtitle {
          Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 8)
      trailing
      if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3) }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .frame(minHeight: 28)
    .contentShape(Rectangle())
  }
}

extension Row where Trailing == EmptyView {
  init(icon: (symbol: String, color: Color)? = nil, title: String, subtitle: String? = nil, destructive: Bool = false, chevron: Bool = false) {
    self.init(icon: icon, title: title, subtitle: subtitle, destructive: destructive, chevron: chevron) { EmptyView() }
  }
}

// MARK: - Segmented control

/// The sliding segmented control from the prototype.
struct Seg<T: Hashable>: View {
  var options: [(value: T, title: String, symbol: String?)]
  @Binding var selection: T
  @Namespace private var ns

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(options.enumerated()), id: \.offset) { _, o in
        Button {
          withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { selection = o.value }
        } label: {
          HStack(spacing: 5) {
            if let s = o.symbol { Image(systemName: s).font(.system(size: 13, weight: .semibold)) }
            Text(o.title).lineLimit(1).minimumScaleFactor(0.8)
          }
          .font(.system(size: 13.5, weight: selection == o.value ? .semibold : .medium))
          .foregroundStyle(selection == o.value ? Theme.ink : Theme.ink2)
          .frame(maxWidth: .infinity)
          .frame(height: 32)
          .background {
            if selection == o.value {
              RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.rim, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                .matchedGeometryEffect(id: "seg", in: ns)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(2)
    .background(Theme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
  }
}

// MARK: - Toast

struct ToastView: View {
  var spec: ToastSpec
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: spec.symbol).font(.system(size: 15, weight: .semibold))
      Text(spec.text).font(.system(size: 14, weight: .semibold)).lineLimit(1)
    }
    .foregroundStyle(.white)
    .padding(.leading, 12)
    .padding(.trailing, 16)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
    .background(Color(hex: 0x222838, opacity: 0.86), in: Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    .padding(.horizontal, 20)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Skeletons

struct Skeleton: View {
  var width: CGFloat? = nil
  var height: CGFloat = 14
  var radius: CGFloat = 10
  @State private var phase: CGFloat = -1

  var body: some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
      .fill(Theme.skeleton)
      .frame(width: width, height: height)
      .overlay {
        GeometryReader { geo in
          LinearGradient(colors: [.clear, Theme.skeleton2, .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: geo.size.width * 0.6)
            .offset(x: phase * geo.size.width * 1.6)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      }
      .onAppear {
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
      }
  }
}

// MARK: - Empty and error

struct ErrorBanner: View {
  var title: String
  var message: String
  var retry: (() -> Void)?
  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "wifi.slash").foregroundStyle(Theme.ink2).padding(.top, 1)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 15, weight: .semibold))
        Text(message).font(.system(size: 13)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
        if let retry {
          Button(action: retry) {
            Label(t("retry"), systemImage: "arrow.clockwise").font(.system(size: 13.5, weight: .semibold))
              .padding(.horizontal, 14).frame(height: 32).background(Theme.cardHi, in: Capsule())
          }
          .buttonStyle(.plain).padding(.top, 8)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .brbCard(radius: 18)
  }
}

struct OfflineBar: View {
  var text: String
  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: "wifi.slash").font(.system(size: 14))
      Text(text).font(.system(size: 13))
      Spacer(minLength: 0)
    }
    .foregroundStyle(Theme.ink2)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}
