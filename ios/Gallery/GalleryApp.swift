import SwiftUI
import WidgetKit

/// The widgets, the Live Activity and the Dynamic Island drawn in an ordinary app, so a screenshot can show
/// them. It is not part of the shipped app: only the BRBGallery scheme builds it (see ios/scripts/shots.sh).
/// `-page home1|home2|home3|lock|live1|live2|island1|island2|island3` picks what is on screen, `-dark 0` the light look.
@main
struct GalleryApp: App {
  var body: some Scene {
    WindowGroup { GalleryView() }
  }
}

struct GalleryView: View {
  private let page = UserDefaults.standard.string(forKey: "page") ?? "home"
  private let dark = UserDefaults.standard.object(forKey: "dark") as? Bool ?? true

  var body: some View {
    ZStack {
      Color.dyn(0x0b0f1c, 0xf2f3f8).ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          switch page {
          case "home2": HomePage.mediums
          case "home3": HomePage.others
          case "lock": LockPage()
          case "live1": ActivityPage(range: 0..<4)
          case "live2": ActivityPage(range: 4..<8)
          case "island1": IslandPage(range: 0..<3)
          case "island2": IslandPage(range: 3..<6)
          case "island3": IslandPage(range: 6..<8)
          default: HomePage.smalls
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .preferredColorScheme(dark ? .dark : .light)
  }
}

// MARK: - Samples

enum GallerySample {
  static let info: [String: Any] = ["name": "Allen's MacBook Pro", "model": "MacBook Pro 14″", "batt": 82, "chg": false]

  static func snap(_ id: String, _ name: String, online: Bool = true, _ state: [String: Any]) -> MacSnapshot {
    let t0 = Date().ms
    let view = RelayView(json: ["v": 3, "level": "owner", "online": online, "state": state])
    return MacSnapshot(id: id, name: name, model: "MacBook Pro", view: view, lastSeen: t0, fetched: t0)
  }

  static func state(_ phase: String, _ extra: [String: Any] = [:]) -> [String: Any] {
    let t0 = Date().ms
    var s: [String: Any] = ["phase": phase, "since": t0 - 25 * 60_000, "place": "cafe", "mac": info]
    for (k, v) in extra { s[k] = v }
    return s
  }

  static var guarding: MacSnapshot { snap("g", "Allen's MacBook Pro", state("armed", ["bumps": 2])) }
  static var arming: MacSnapshot {
    snap("a", "Allen's MacBook Pro", state("arming", ["armEnd": Date().ms + 14_000]))
  }
  static var warn: MacSnapshot {
    let t0 = Date().ms
    return snap(
      "w", "Allen's MacBook Pro",
      state("triggered", ["at": t0 - 4_000, "trigger": "touch", "stage": "soft", "softEnd": t0 + 6_000]))
  }
  static var alarm: MacSnapshot {
    let t0 = Date().ms
    return snap(
      "x", "Allen's MacBook Pro",
      state("triggered", ["at": t0 - 56_000, "trigger": "lift", "siren": true, "stage": "siren"]))
  }
  static var idle: MacSnapshot {
    snap("i", "Allen's MacBook Pro", state("idle", ["lastEnd": Date().ms - 2 * 3_600_000]))
  }
  static var offline: MacSnapshot {
    snap("o", "Studio MacBook Air", online: false, state("armed"))
  }
  static var session: SessionRecord {
    let t0 = Date().ms
    return SessionRecord(
      id: "s", start: t0 - 5 * 3_600_000, end: t0 - 3 * 3_600_000, place: .cafe, bumps: 1, kind: .quiet)
  }

  static func entry(_ macs: [MacSnapshot], locked: Bool = false, latest: Bool = false) -> BRBWidgetEntry {
    BRBWidgetEntry(date: Date(), macs: macs, fetched: Date().ms, latest: latest ? session : nil, locked: locked)
  }
}

// MARK: - Widgets on the home screen and the Lock Screen

struct WidgetBox: View {
  var entry: BRBWidgetEntry
  var family: WidgetFamily

  private var size: CGSize {
    switch family {
    case .systemSmall: return CGSize(width: 170, height: 170)
    case .systemMedium: return CGSize(width: 364, height: 170)
    case .accessoryCircular: return CGSize(width: 76, height: 76)
    case .accessoryRectangular: return CGSize(width: 172, height: 76)
    default: return CGSize(width: 240, height: 22)
    }
  }

  private var accessory: Bool {
    switch family {
    case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
    default: return false
    }
  }

  var body: some View {
    ZStack {
      if accessory {
        Color.white.opacity(0.12)
      } else {
        WStyle.background(for: entry.locked ? nil : entry.focus?.look)
      }
      BRBWidgetRootView(entry: entry)
        .environment(\.widgetFamily, family)
    }
    .frame(width: size.width, height: size.height)
    .clipShape(RoundedRectangle(cornerRadius: accessory ? 18 : 24, style: .continuous))
  }
}

enum HomePage {
  static var smalls: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Home screen · small").font(.headline)
      HStack(spacing: 16) {
        WidgetBox(entry: GallerySample.entry([GallerySample.guarding]), family: .systemSmall)
        WidgetBox(entry: GallerySample.entry([GallerySample.alarm]), family: .systemSmall)
      }
      HStack(spacing: 16) {
        WidgetBox(entry: GallerySample.entry([GallerySample.idle]), family: .systemSmall)
        WidgetBox(entry: GallerySample.entry([GallerySample.warn]), family: .systemSmall)
      }
      HStack(spacing: 16) {
        WidgetBox(entry: GallerySample.entry([GallerySample.arming]), family: .systemSmall)
        WidgetBox(entry: GallerySample.entry([GallerySample.offline]), family: .systemSmall)
      }
    }
  }

  static var mediums: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Home screen · medium").font(.headline)
      WidgetBox(entry: GallerySample.entry([GallerySample.guarding, GallerySample.offline]), family: .systemMedium)
      WidgetBox(entry: GallerySample.entry([GallerySample.idle], latest: true), family: .systemMedium)
      WidgetBox(entry: GallerySample.entry([GallerySample.alarm, GallerySample.guarding]), family: .systemMedium)
    }
  }

  static var others: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("No Mac · locked").font(.headline)
      HStack(spacing: 16) {
        WidgetBox(entry: GallerySample.entry([]), family: .systemSmall)
        WidgetBox(entry: GallerySample.entry([GallerySample.guarding], locked: true), family: .systemSmall)
      }
      WidgetBox(entry: GallerySample.entry([]), family: .systemMedium)
      WidgetBox(entry: GallerySample.entry([GallerySample.guarding], locked: true), family: .systemMedium)
    }
  }
}

struct LockPage: View {
  private let model = [
    GallerySample.guarding, GallerySample.warn, GallerySample.alarm, GallerySample.idle, GallerySample.offline,
  ]

  var body: some View {
    Text("Lock Screen widgets").font(.headline)
    ForEach(model.indices, id: \.self) { i in
      HStack(spacing: 12) {
        WidgetBox(entry: GallerySample.entry([model[i]]), family: .accessoryCircular)
        WidgetBox(entry: GallerySample.entry([model[i]]), family: .accessoryRectangular)
      }
      WidgetBox(entry: GallerySample.entry([model[i]]), family: .accessoryInline)
    }
  }
}

struct ActivityPage: View {
  var range: Range<Int>

  var body: some View {
    Text("Live Activity").font(.headline)
    ForEach(Array(GalleryActivities.states.enumerated()), id: \.offset) { i, state in
      if range.contains(i) {
        ActivityCard(model: WActivityModel(state: state, macName: "Allen's MacBook Pro", macID: "x"))
      }
    }
  }
}

enum GalleryActivities {
  static var states: [BRBActivityAttributes.ContentState] {
    let t0 = Date().ms
    return [
      .init(look: "arming", armEnd: t0 + 14_000),
      .init(look: "armed", since: t0 - 12 * 60_000, bumps: 2),
      .init(look: "warn", at: t0 - 4_000, softEnd: t0 + 6_000, trigger: "touch"),
      .init(look: "alarm", at: t0 - 56_000, trigger: "lift"),
      .init(look: "hushed", at: t0 - 80_000, trigger: "lift"),
      .init(look: "back", at: t0 - 80_000, trigger: "lift"),
      .init(look: "clear", at: t0 - 90_000, trigger: "lift", by: "phone"),
      .init(look: "offline"),
    ]
  }
}

struct ActivityCard: View {
  var model: WActivityModel

  var body: some View {
    BRBLockActivityView(model: model)
      .background(model.tint)
      .background(Color.black)
      .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
  }
}

struct IslandPage: View {
  var range: Range<Int>

  var body: some View {
    Text("Dynamic Island").font(.headline)
    ForEach(Array(GalleryActivities.states.enumerated()), id: \.offset) { i, state in
      let model = WActivityModel(state: state, macName: "Allen's MacBook Pro", macID: "x")
      if range.contains(i) {
      VStack(spacing: 8) {
        HStack(spacing: 10) {
          WShield(look: model.shield, size: 18)
          Spacer()
          BRBIslandCompactTrailing(model: model)
        }
        .padding(.horizontal, 14)
        .frame(width: 150, height: 36)
        .background(Color.black, in: Capsule())
        ExpandedIsland(model: model)
      }
      }
    }
  }
}

struct ExpandedIsland: View {
  var model: WActivityModel

  var body: some View {
    VStack(spacing: 6) {
      HStack(alignment: .center) {
        BRBIslandLeading(model: model)
        Spacer(minLength: 4)
        BRBIslandCenter(model: model)
        Spacer(minLength: 4)
        BRBIslandTrailing(model: model)
      }
      BRBIslandBottom(model: model)
    }
    .foregroundStyle(Color.white)
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .frame(width: 366)
    .background(Color.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
    .environment(\.colorScheme, .dark)
  }
}
