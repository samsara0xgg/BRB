import SwiftUI
import WidgetKit

/// The home screen and Lock Screen widget: the focus Mac's shield, state and one button.
struct BRBStatusWidget: Widget {
  static let kind = "com.allen.brb.status"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: BRBStatusWidget.kind, provider: BRBWidgetProvider()) { entry in
      BRBWidgetRootView(entry: entry)
    }
    .configurationDisplayName(t("wi_name"))
    .description(t("wi_desc"))
    .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

struct BRBWidgetRootView: View {
  @Environment(\.widgetFamily) private var family
  let entry: BRBWidgetEntry

  private var isAccessory: Bool {
    switch family {
    case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
    default: return false
    }
  }

  /// Where a tap on the widget goes.
  private var link: URL {
    if entry.locked { return BRBDeepLink.pro }
    guard let focus = entry.focus else { return BRBDeepLink.addMac }
    return focus.look.isAlarm ? BRBDeepLink.alarm(focus.id) : BRBDeepLink.mac(focus.id)
  }

  var body: some View {
    content
      .widgetURL(link)
      .containerBackground(for: .widget) {
        if isAccessory {
          Color.clear
        } else {
          WStyle.background(for: entry.locked ? nil : entry.focus?.look)
        }
      }
  }

  @ViewBuilder private var content: some View {
    switch family {
    case .systemSmall:
      BRBSmallView(entry: entry)
    case .accessoryCircular:
      BRBCircularView(entry: entry)
    case .accessoryRectangular:
      BRBRectangularView(entry: entry)
    case .accessoryInline:
      BRBInlineView(entry: entry)
    default:
      BRBMediumView(entry: entry)
    }
  }
}

// MARK: - Small

struct BRBSmallView: View {
  let entry: BRBWidgetEntry

  var body: some View {
    if entry.locked {
      BRBLockedView(compact: true)
    } else if let s = entry.focus {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top, spacing: 4) {
          WShield(look: s.look.shield, size: 40, progress: 0.5)
          Spacer(minLength: 2)
          if let clock = WClockKind.of(s) {
            WClockView(
              kind: clock, now: entry.date, size: 18, color: Theme.text(for: s.look), width: 64, alignment: .trailing)
              .padding(.top, 2)
          }
        }
        Spacer(minLength: 4)
        Text(WText.title(s, now: entry.date))
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.text(for: s.look))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text(s.name)
          .font(.system(size: 12))
          .foregroundStyle(Theme.ink2)
          .lineLimit(1)
        WActionButton(snap: s, height: 30)
          .padding(.top, 8)
      }
    } else {
      BRBEmptyView(compact: true)
    }
  }
}

// MARK: - Medium

struct BRBMediumView: View {
  let entry: BRBWidgetEntry

  var body: some View {
    if entry.locked {
      BRBLockedView(compact: false)
    } else if let s = entry.focus {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          Link(destination: BRBDeepLink.mac(s.id)) { BRBMacRow(snap: s, now: entry.date) }
          if let other = entry.others.first {
            Link(destination: BRBDeepLink.mac(other.id)) { BRBMacRow(snap: other, now: entry.date) }
          } else if let r = entry.latest {
            BRBRecentView(record: r)
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Rectangle().fill(Theme.hair).frame(width: 1)

        VStack(alignment: .leading, spacing: 2) {
          if let clock = WClockKind.of(s) {
            WClockView(
              kind: clock, now: entry.date, size: 28, color: Theme.text(for: s.look), width: 124, alignment: .leading)
          } else {
            Text("BRB")
              .font(.rounded(28, .semibold))
              .foregroundStyle(Theme.ink)
          }
          Text(entry.isStale && s.fetched > 0 ? t("wi_updated", Fmt.hm(s.fetched)) : s.state.place.name)
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink2)
            .lineLimit(1)
          Spacer(minLength: 4)
          WActionButton(snap: s, height: 36)
        }
        .frame(width: 124)
      }
    } else {
      BRBEmptyView(compact: false)
    }
  }
}

/// A Mac's shield, name and one line about it.
struct BRBMacRow: View {
  let snap: MacSnapshot
  let now: Date

  var body: some View {
    HStack(spacing: 9) {
      WShield(look: snap.look.shield, size: 30)
      VStack(alignment: .leading, spacing: 1) {
        Text(snap.name)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Theme.ink)
          .lineLimit(1)
        Text(WText.line(snap, now: now))
          .font(.system(size: 12))
          .foregroundStyle(WStyle.status(for: snap.look))
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
  }
}

/// "LATEST  Away 2 h, nobody touched it · 14:05"
struct BRBRecentView: View {
  let record: SessionRecord

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(t("wg_recent"))
        .font(.system(size: 11, weight: .semibold))
        .textCase(.uppercase)
        .foregroundStyle(Theme.ink3)
      Text(BRBSessionText.line(record) + " · " + Fmt.hm(record.end))
        .font(.system(size: 12))
        .foregroundStyle(Theme.ink2)
        .lineLimit(2)
    }
  }
}

// MARK: - Nothing paired, or not Pro

struct BRBEmptyView: View {
  let compact: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        WShield(look: .idle, size: compact ? 40 : 34)
        if !compact {
          VStack(alignment: .leading, spacing: 1) {
            Text("BRB").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(t("noMacs")).font(.system(size: 12)).foregroundStyle(Theme.ink2).lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }
      if compact {
        Spacer(minLength: 4)
        Text("BRB").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
        Text(t("noMacs")).font(.system(size: 12)).foregroundStyle(Theme.ink2).lineLimit(1)
      }
      Spacer(minLength: 6)
      WPill(title: t("emptyDevT"), style: .ghost, height: compact ? 30 : 36)
    }
  }
}

struct BRBLockedView: View {
  let compact: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        WShield(look: .idle, size: compact ? 40 : 34)
        if !compact {
          VStack(alignment: .leading, spacing: 1) {
            Text(t("pwT")).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
            Text(t("wv_needCloud")).font(.system(size: 12)).foregroundStyle(Theme.ink2).lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }
      if compact {
        Spacer(minLength: 4)
        Text(t("pwT")).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
        Text(t("wv_needCloud")).font(.system(size: 12)).foregroundStyle(Theme.ink2).lineLimit(1)
      }
      Spacer(minLength: 6)
      WPill(title: t("upgrade"), symbol: "lock.fill", style: .ghost, height: compact ? 30 : 36)
    }
  }
}

// MARK: - Lock Screen

struct BRBCircularView: View {
  let entry: BRBWidgetEntry

  var body: some View {
    ZStack {
      AccessoryWidgetBackground()
      if entry.locked {
        Image(systemName: "lock.fill").font(.system(size: 18, weight: .semibold)).widgetAccentable()
      } else {
        WShield(look: entry.focus?.look.shield ?? .idle, size: 30, mono: true).widgetAccentable()
      }
    }
  }
}

struct BRBRectangularView: View {
  let entry: BRBWidgetEntry

  var body: some View {
    if entry.locked {
      HStack(spacing: 8) {
        Image(systemName: "lock.fill").font(.system(size: 18, weight: .semibold)).widgetAccentable()
        VStack(alignment: .leading, spacing: 1) {
          Text(t("pwT")).font(.headline).widgetAccentable()
          Text(t("wv_needCloud")).font(.caption)
        }
        Spacer(minLength: 0)
      }
    } else if let s = entry.focus {
      HStack(spacing: 8) {
        WShield(look: s.look.shield, size: 28, mono: true).widgetAccentable()
        VStack(alignment: .leading, spacing: 1) {
          Text(WText.title(s, now: entry.date)).font(.headline).widgetAccentable().lineLimit(1)
          Text(s.name).font(.caption).lineLimit(1)
          if let clock = WClockKind.of(s) {
            WClockView(kind: clock, now: entry.date, size: 12, color: Color.primary, width: nil, alignment: .leading)
          } else {
            Text(WText.line(s, now: entry.date)).font(.caption).lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }
    } else {
      HStack(spacing: 8) {
        WShield(look: .idle, size: 28, mono: true).widgetAccentable()
        VStack(alignment: .leading, spacing: 1) {
          Text("BRB").font(.headline).widgetAccentable()
          Text(t("noMacs")).font(.caption).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
    }
  }
}

struct BRBInlineView: View {
  let entry: BRBWidgetEntry

  private func symbol(_ look: Look) -> String {
    switch look {
    case .idle: return "shield"
    case .arming, .armed, .partial, .test: return "shield.fill"
    case .warn, .alarm: return "exclamationmark.shield.fill"
    case .offline: return "wifi.slash"
    }
  }

  var body: some View {
    if entry.locked {
      Label("BRB · " + t("wv_needCloud"), systemImage: "lock.fill")
    } else if let s = entry.focus {
      Label(s.plain(now: entry.date.ms) + " · " + s.name, systemImage: symbol(s.look))
    } else {
      Label("BRB · " + t("emptyDevT"), systemImage: "shield")
    }
  }
}
