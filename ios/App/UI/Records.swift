import SwiftUI

// MARK: - Words for a session

extension SessionRecord {
  var shield: ShieldLook {
    switch kind {
    case .alarm: return .alarm
    case .test: return .test
    case .quiet: return .armed
    }
  }

  /// `how_*` for an alarm: the way out, as the Mac named it.
  var howKey: String {
    switch how ?? "" {
    case "phone": return "how_face"
    case "watch": return "how_watch"
    default: return "how_touch"
    }
  }

  var triggerKind: Trigger.Kind { trigger?.kind ?? .lift }

  /// The one line a row and the detail page lead with.
  var line: String {
    switch kind {
    case .alarm: return t("rl_alarm", triggerKind.phrase, t(howKey))
    case .test: return t("rl_test")
    case .quiet:
      let d = Fmt.duration(duration)
      return bumps > 0 ? t("rl_bumps", d, tn("n_bumps", bumps)) : t("rl_quiet", d)
    }
  }

  /// "Alarm · Picked up".
  var alarmTitle: String { t("rl_alarmS", triggerKind.title) }

  /// A quiet session has no timeline of its own; this is the start, the bumps it ignored, and the end.
  var timeline: [EventItem] {
    if !events.isEmpty { return events.sorted { $0.t < $1.t } }
    var out = [EventItem(t: start, e: "armed")]
    if bumps > 0 {
      for i in 0..<bumps {
        out.append(EventItem(t: start + Ms(Double(duration) * Double(i + 1) / Double(bumps + 1)), e: "bump"))
      }
    }
    out.append(EventItem(t: end, e: "cancelled"))
    return out
  }

  var endedOnPhone: Bool { how == "phone" }
}

func capitalizedFirst(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

// MARK: - Row

struct RowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.background(configuration.isPressed ? Theme.cardHi : Color.clear)
  }
}

struct RecordRow: View {
  var mac: MacModel
  var record: SessionRecord
  /// Show the day in the subtitle (the recent list on a Mac's page) instead of under a day heading.
  var showDay = false
  var showMac = false

  private var alarm: Bool { record.kind == .alarm }

  private var subtitle: String {
    let how = alarm ? capitalizedFirst(t(record.howKey)) + " · " : ""
    let day = showDay ? Fmt.dayLabel(record.end) + " " : ""
    return how + day + Fmt.hm(record.start) + "–" + Fmt.hm(record.end) + " · " + record.place.name
  }

  var body: some View {
    NavigationLink(value: Route.record(mac: mac.id, id: record.id)) {
      HStack(spacing: 12) {
        ShieldView(look: record.shield, size: 30)
          .foregroundStyle(Theme.ink2)
          .frame(width: 30, height: 30)
        VStack(alignment: .leading, spacing: 1) {
          Text(alarm ? record.alarmTitle : record.line)
            .font(.system(size: 15.5, weight: .semibold))
            .foregroundStyle(alarm ? Theme.textRed : Theme.ink)
            .multilineTextAlignment(.leading)
          if showMac {
            Text(mac.name).font(.system(size: 12.5)).foregroundStyle(Theme.ink3)
          }
          Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.ink3).multilineTextAlignment(.leading)
        }
        Spacer(minLength: 6)
        if alarm, let first = record.photos.first {
          RelayPhoto(mac: mac, ms: first)
            .frame(width: 40, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink3)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowButtonStyle())
  }
}

// MARK: - Records tab

struct RecordEntry: Identifiable {
  let mac: MacModel
  let record: SessionRecord
  var id: String { mac.id + "/" + record.id }
}

extension AppStore {
  /// Every session of every Mac, newest first.
  var allRecords: [RecordEntry] {
    macs.flatMap { m in m.sessions.map { RecordEntry(mac: m, record: $0) } }.sorted { $0.record.end > $1.record.end }
  }
}

struct RecordsView: View {
  @Environment(AppStore.self) private var store

  private var filtered: [RecordEntry] {
    store.allRecords.filter { e in
      (!store.recordFilterAlarms || e.record.kind == .alarm) && (store.recordMac == nil || e.mac.id == store.recordMac)
    }
  }

  private var week: (n: Int, hours: Int, alarms: Int) {
    let from = nowMs() - 7 * 86_400_000
    let rs = store.allRecords.filter {
      $0.record.kind != .test && $0.record.end > from && (store.recordMac == nil || $0.mac.id == store.recordMac)
    }
    let ms = rs.reduce(Ms(0)) { $0 + $1.record.duration }
    return (rs.count, Int((Double(ms) / 3_600_000).rounded()), rs.filter { $0.record.kind == .alarm }.count)
  }

  private var days: [(key: DateComponents, label: String, items: [RecordEntry])] {
    var out: [(key: DateComponents, label: String, items: [RecordEntry])] = []
    for e in filtered {
      let key = Fmt.dayKey(e.record.end)
      if let i = out.firstIndex(where: { $0.key == key }) {
        out[i].items.append(e)
      } else {
        out.append((key, Fmt.dayLabel(e.record.end), [e]))
      }
    }
    return out
  }

  private var loading: Bool {
    store.launch.pageState == "loading" || (store.allRecords.isEmpty && store.macs.contains { $0.sessionsState == .loading || $0.sessionsState == .idle })
  }

  private var failed: Bool {
    store.launch.pageState == "error" || (store.allRecords.isEmpty && !store.macs.isEmpty && store.macs.allSatisfy { $0.sessionsState == .failed })
  }

  var body: some View {
    @Bindable var store = store
    ScrollView {
      VStack(spacing: 0) {
        if store.phoneOffline || store.launch.pageState == "offline" { OfflineBar(text: t("obarPhone")).padding(.bottom, 10) }
        if failed {
          ErrorBanner(title: t("errT"), message: t("errS")) { Task { await store.loadAllHistory(force: true) } }
        } else if loading {
          RecordsSkeleton()
        } else if store.allRecords.isEmpty || store.launch.pageState == "empty" {
          EmptyState(title: t("emptyRecT"), message: t("emptyRecP")) { RecordsArt() }
        } else {
          content
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 30)
    }
    .background(Backdrop())
    .navigationTitle(t("tabRecords"))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        RoundIconButton(symbol: "square.and.arrow.up", label: t("shareT")) { store.sheet = .share(mac: "", record: nil) }
      }
    }
    .task { await store.loadAllHistory() }
    .refreshable { await store.loadAllHistory(force: true) }
  }

  @ViewBuilder private var content: some View {
    @Bindable var store = store
    let w = week
    Text(t("recWeek")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 4)
    HStack(spacing: 8) {
      StatTile(value: w.n, unit: t("st_sessions"), caption: t("st_sessionsL"))
      StatTile(value: w.hours, unit: t("st_hours"), caption: t("st_hoursL"))
      StatTile(value: w.alarms, unit: t("st_stopped"), caption: t("st_stoppedL"), alarm: w.alarms > 0)
    }
    .padding(.top, 8)

    Seg(
      options: [(value: false, title: t("f_all"), symbol: nil), (value: true, title: t("f_alarm"), symbol: nil)],
      selection: $store.recordFilterAlarms
    )
    .padding(.top, 14)

    if store.macs.count > 1 {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          MacFilterChip(title: t("f_allMacs"), on: store.recordMac == nil) { store.recordMac = nil }
          ForEach(store.macs) { m in
            MacFilterChip(title: m.name, on: store.recordMac == m.id) { store.recordMac = m.id }
          }
        }
      }
      .padding(.top, 10)
    }

    if filtered.isEmpty {
      Text(t("noAlarms")).font(.system(size: 14)).foregroundStyle(Theme.ink3).frame(maxWidth: .infinity).padding(.vertical, 36)
    }

    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
      Text(day.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 20).padding(.bottom, 8)
      Grp {
        ForEach(Array(day.items.enumerated()), id: \.element.id) { i, e in
          if i > 0 { Hairline() }
          RecordRow(mac: e.mac, record: e.record, showMac: store.macs.count > 1)
        }
      }
    }

    FootNote(symbol: "lock.fill", text: t(store.pro ? "recFootC" : "recFootF")).padding(.top, 18)
  }
}

struct StatTile: View {
  var value: Int
  var unit: String
  var caption: String
  var alarm = false
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text("\(value)").font(.rounded(25, .semibold)).monospacedDigit().foregroundStyle(alarm ? Theme.textRed : Theme.ink)
        Text(unit).font(.system(size: 12)).foregroundStyle(Theme.ink3)
      }
      Text(caption).font(.system(size: 12)).foregroundStyle(Theme.ink3).lineLimit(1).minimumScaleFactor(0.8)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
    .brbCard(radius: 18)
  }
}

struct MacFilterChip: View {
  var title: String
  var on: Bool
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(title).font(.system(size: 13, weight: on ? .semibold : .regular)).lineLimit(1)
        .foregroundStyle(on ? Theme.bg : Theme.ink2)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(on ? Theme.ink : Theme.cardHi, in: Capsule())
    }
    .buttonStyle(.plain)
  }
}

/// The small lock line under a list: "Only you can see this".
struct FootNote: View {
  var symbol: String
  var text: String
  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: symbol).font(.system(size: 11))
      Text(text).font(.system(size: 12.5)).multilineTextAlignment(.center)
    }
    .foregroundStyle(Theme.ink3)
    .frame(maxWidth: .infinity)
  }
}

struct RecordsSkeleton: View {
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) { ForEach(0..<3, id: \.self) { _ in Skeleton(height: 64, radius: 18) } }
      Skeleton(height: 36, radius: 11).padding(.top, 14)
      ForEach(0..<2, id: \.self) { _ in
        Skeleton(width: 90, height: 13).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 22).padding(.bottom, 10).padding(.horizontal, 4)
        Grp {
          ForEach(0..<3, id: \.self) { _ in
            HStack(spacing: 12) {
              Skeleton(width: 28, height: 28, radius: 9)
              VStack(alignment: .leading, spacing: 6) {
                Skeleton(width: 170, height: 14)
                Skeleton(width: 110, height: 11)
              }
              Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
          }
        }
      }
    }
  }
}

// MARK: - One session

struct RecordDetailView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var macID: String
  var recordID: String
  @State private var viewer: PhotoViewerSpec?

  private var mac: MacModel? { store.mac(macID) }
  private var record: SessionRecord? { mac?.sessions.first { $0.id == recordID } }

  var body: some View {
    ScrollView {
      if let mac, let r = record {
        content(mac, r)
      } else if store.launch.pageState == "loading" {
        VStack(spacing: 14) {
          Skeleton(width: 58, height: 58, radius: 20)
          Skeleton(width: 220, height: 22)
          Skeleton(height: 150, radius: 20)
          Skeleton(height: 190, radius: 20)
        }
        .padding(16)
      }
    }
    .background(Backdrop())
    .navigationTitle(t("rdT"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if let mac, let r = record {
        ToolbarItem(placement: .topBarTrailing) {
          RoundIconButton(symbol: "square.and.arrow.up", label: t("shareT")) {
            store.sheet = r.kind == .alarm ? .evidence(mac: mac.id, record: r.id) : .share(mac: mac.id, record: r.id)
          }
        }
      }
    }
    .fullScreenCover(item: $viewer) { spec in
      if let mac { PhotoViewer(mac: mac, photos: spec.photos, start: spec.index) }
    }
  }

  @ViewBuilder private func content(_ mac: MacModel, _ r: SessionRecord) -> some View {
    let alarm = r.kind == .alarm
    VStack(spacing: 0) {
      if store.phoneOffline || store.launch.pageState == "offline" { OfflineBar(text: t("rd_off")).padding(.bottom, 10) }

      VStack(spacing: 2) {
        ShieldView(look: r.shield, size: 58).foregroundStyle(Theme.ink2).padding(.bottom, 8)
        Text(r.line).font(.system(size: 22, weight: .bold)).multilineTextAlignment(.center)
          .foregroundStyle(alarm ? Theme.textRed : Theme.ink)
        Text(mac.name + " · " + Fmt.dayLabel(r.end)).font(.system(size: 14)).foregroundStyle(Theme.ink2)
      }
      .padding(.top, 10).padding(.horizontal, 20).padding(.bottom, 4)

      facts(r, alarm: alarm).padding(.top, 14)

      if alarm {
        if store.launch.pageState == "error" {
          ErrorBanner(title: t("rd_err"), message: t("rd_errS"), retry: nil).padding(.top, 14)
        } else if !r.photos.isEmpty {
          Text(t("rd_photos", r.photos.count)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 22).padding(.bottom, 8)
          let sorted = r.photos.sorted()
          LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(Array(sorted.enumerated()), id: \.offset) { i, ms in
              Button { viewer = PhotoViewerSpec(photos: sorted, index: i) } label: {
                RelayPhoto(mac: mac, ms: ms).aspectRatio(4 / 3, contentMode: .fit)
              }
              .buttonStyle(.plain)
            }
          }
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
      }

      Text(t("rd_tl")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.ink2)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 22).padding(.bottom, 8)
      Grp { EventList(events: r.timeline, mac: mac, size: 14).padding(.horizontal, 14).padding(.vertical, 6) }

      Grp {
        if alarm {
          Button { Task { await store.savePhotos(of: mac, photos: r.photos.sorted()) } } label: {
            Row(icon: ("square.and.arrow.down", Theme.tint), title: t("rd_save"))
          }
          .buttonStyle(RowButtonStyle())
          Hairline()
          Button { store.sheet = .evidence(mac: mac.id, record: r.id) } label: {
            Row(icon: ("doc.text", Theme.tint), title: t("rd_export"), chevron: true)
          }
          .buttonStyle(RowButtonStyle())
        } else {
          Button { store.sheet = .share(mac: mac.id, record: r.id) } label: {
            Row(icon: ("square.and.arrow.up", Theme.tint), title: t("rd_share"), chevron: true)
          }
          .buttonStyle(RowButtonStyle())
        }
        Hairline()
        Button {
          store.present(
            AlertSpec(
              title: t("delT"), message: t("delP"),
              actions: [
                .init(t("cancel"), role: .cancel),
                .init(t("delete"), role: .destructive) {
                  Task {
                    await store.deleteRecord(r, of: mac)
                    dismiss()
                  }
                },
              ]))
        } label: {
          Row(icon: ("trash", Theme.gray), title: t("rd_delete"), destructive: true)
        }
        .buttonStyle(RowButtonStyle())
      }
      .padding(.top, 22)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 30)
  }

  private func facts(_ r: SessionRecord, alarm: Bool) -> some View {
    let how = alarm ? capitalizedFirst(t(r.howKey)) : t(r.endedOnPhone ? "end_phone" : "end_mac")
    let cells: [(String, String)] = [
      (t("kv_start"), Fmt.hm(r.start)), (t("kv_end"), Fmt.hm(r.end)),
      (t("kv_dur"), Fmt.duration(r.duration)), (t("kv_place"), r.place.name),
      (t("kv_bumps"), t("times", r.bumps)), (t("kv_how"), how),
    ]
    return VStack(spacing: 0) {
      ForEach(0..<3, id: \.self) { row in
        if row > 0 { Rectangle().fill(Theme.hair).frame(height: 1) }
        HStack(spacing: 0) {
          Fact(label: cells[row * 2].0, value: cells[row * 2].1)
          Rectangle().fill(Theme.hair).frame(width: 1)
          Fact(label: cells[row * 2 + 1].0, value: cells[row * 2 + 1].1)
        }
      }
    }
    .brbCard(radius: 20)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

private struct Fact: View {
  var label: String
  var value: String
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(label).font(.system(size: 12)).foregroundStyle(Theme.ink3)
      Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.85)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Full-size photos

struct PhotoViewerSpec: Identifiable {
  let id = UUID()
  var photos: [Ms]
  var index: Int
}

struct PhotoViewer: View {
  @Environment(\.dismiss) private var dismiss
  var mac: MacModel
  var photos: [Ms]
  @State private var index: Int

  init(mac: MacModel, photos: [Ms], start: Int) {
    self.mac = mac
    self.photos = photos
    _index = State(initialValue: start)
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.black.ignoresSafeArea()
      TabView(selection: $index) {
        ForEach(Array(photos.enumerated()), id: \.offset) { i, ms in
          RelayPhoto(mac: mac, ms: ms).aspectRatio(4 / 3, contentMode: .fit).tag(i)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
      .ignoresSafeArea()
      Button { dismiss() } label: {
        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
          .frame(width: 36, height: 36).background(.black.opacity(0.5), in: Circle())
      }
      .padding(16)
      .accessibilityLabel(t("cancel"))
    }
    .preferredColorScheme(.dark)
  }
}
