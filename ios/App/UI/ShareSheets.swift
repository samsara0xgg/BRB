import SwiftUI
import UniformTypeIdentifiers

// MARK: - The app mark

/// The amber app icon, small, for cards and reports.
struct AppMark: View {
  var size: CGFloat = 22
  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
      .fill(LinearGradient(colors: [Theme.amberHi, Theme.amberDeep], startPoint: .top, endPoint: .bottom))
      .frame(width: size, height: size)
      .overlay { ShieldView(look: .armed, size: size * 0.72, mono: true).foregroundStyle(Theme.amberInk) }
      .accessibilityHidden(true)
  }
}

// MARK: - Share card

struct ShareStats {
  struct Seg {
    var left: Double
    var width: Double
  }
  var ms: Ms = 0
  var bumps = 0
  var segs: [Seg] = []
  var from: Ms = nowMs() - 86_400_000

  var duration: String {
    ms >= 3_600_000 ? Fmt.hours(Int((Double(ms) / 3_600_000).rounded())) : t("mins", max(1, Int((Double(ms) / 60_000).rounded())))
  }
  var headline: String { t("shareH", duration, tn("n_bumps", bumps)) }
}

extension AppStore {
  /// The last 24 hours of guarding across the Macs (or one session), for the share card. No photos, no faces.
  func shareStats(mac id: String, record: String?) -> ShareStats {
    let day: Ms = 86_400_000
    let now = nowMs()
    var stats = ShareStats()
    func add(_ start: Ms, _ end: Ms, bumps: Int) {
      let s = max(start, stats.from)
      guard end > s else { return }
      stats.ms += end - s
      stats.bumps += bumps
      stats.segs.append(.init(left: Double(s - stats.from) / Double(day) * 100, width: Double(end - s) / Double(day) * 100))
    }
    if let record, let m = mac(id), let r = m.sessions.first(where: { $0.id == record }) {
      stats.from = r.end - day
      add(r.start, r.end, bumps: r.bumps)
      return stats
    }
    stats.from = now - day
    for m in macs {
      for r in m.sessions where r.kind != .test && r.end > stats.from { add(r.start, r.end, bumps: r.bumps) }
      if m.look.isGuarding && m.look != .test { add(m.state.since, now, bumps: m.state.bumps) }
    }
    return stats
  }
}

/// The picture people post: dark, one amber shield, one sentence, the day as a bar.
struct ShareCard: View {
  var stats: ShareStats

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        AppMark(size: 24)
        Text("BRB").font(.system(size: 16, weight: .heavy))
        Spacer()
        Text(Fmt.dateLong(nowMs())).font(.system(size: 12.5)).opacity(0.7)
      }
      ShieldView(look: .armed, size: 92).padding(.top, 26)
      Text(stats.headline)
        .font(.system(size: 25, weight: .heavy))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 14)
      Text("Be Right Back · " + t("shareSub")).font(.system(size: 14)).opacity(0.7).padding(.top, 6)

      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(.white.opacity(0.12))
          ForEach(Array(stats.segs.enumerated()), id: \.offset) { _, g in
            Capsule().fill(Theme.amber)
              .frame(width: max(5, geo.size.width * g.width / 100))
              .offset(x: geo.size.width * g.left / 100)
          }
        }
      }
      .frame(height: 10)
      .clipShape(Capsule())
      .padding(.top, 24)
      HStack {
        ForEach(0..<5, id: \.self) { i in
          Text(i == 4 ? t("now") : Fmt.hm(stats.from + Ms(i) * 6 * 3_600_000))
            .font(.system(size: 10.5)).monospacedDigit().opacity(0.55)
          if i < 4 { Spacer(minLength: 0) }
        }
      }
      .padding(.top, 6)
    }
    .foregroundStyle(.white)
    .padding(22)
    .frame(width: 330)
    .background(LinearGradient(colors: [Color(hex: 0x1b2440), Color(hex: 0x0b0f1c)], startPoint: .top, endPoint: .bottom))
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
  }
}

struct SheetHeader: View {
  var title: String
  var subtitle: String?
  var close: () -> Void
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 21, weight: .bold))
        if let subtitle { Text(subtitle).font(.system(size: 13.5)).foregroundStyle(Theme.ink2) }
      }
      Spacer()
      RoundIconButton(symbol: "xmark", label: t("cancel"), action: close)
    }
  }
}

struct ShareItem: Identifiable {
  let id = UUID()
  var items: [Any]
}

struct ShareSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var macID: String
  var recordID: String?
  @State private var stats = ShareStats()
  @State private var item: ShareItem?

  var body: some View {
    VStack(spacing: 0) {
      SheetHeader(title: t("shareT"), subtitle: t("shareNoFace")) { dismiss() }
        .padding(.bottom, 16)
      ScrollView {
        VStack(spacing: 18) {
          ShareCard(stats: stats)
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
          HStack(spacing: 12) {
            ShareTarget(symbol: "square.and.arrow.down", title: t("save"), color: Color(hex: 0x5a6070)) { save() }
            ShareTarget(symbol: "square.and.arrow.up", title: t("share"), color: Theme.tint) { share() }
          }
          .padding(.horizontal, 6)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 22)
    .presentationDetents([.large])
    .task {
      await store.loadAllHistory()
      stats = store.shareStats(mac: macID, record: recordID)
    }
    .sheet(item: $item) { it in ActivityView(items: it.items).presentationDetents([.medium, .large]) }
  }

  private func rendered() -> UIImage? {
    let renderer = ImageRenderer(content: ShareCard(stats: stats))
    renderer.scale = 3
    return renderer.uiImage
  }

  private func save() {
    guard let image = rendered() else { return }
    Task {
      if await PhotoExport.save([image]) {
        store.show(t("savedImg"), "square.and.arrow.down")
      } else {
        store.show(t("err_photos"), "exclamationmark.triangle")
      }
    }
  }

  private func share() {
    guard let image = rendered() else { return }
    item = ShareItem(items: [image])
  }
}

struct ShareTarget: View {
  var symbol: String
  var title: String
  var color: Color
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
          .frame(width: 52, height: 52).background(color, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.ink2)
      }
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(PressableStyle())
  }
}

// MARK: - Evidence pack

/// What an evidence pack is made of: one alarm, from the phone's side.
struct EvidenceSource {
  var mac: MacModel
  var at: Ms
  var photos: [Ms]
  var events: [EventItem]
}

extension AppStore {
  func evidenceSource(mac id: String, record: String?) -> EvidenceSource? {
    guard let m = mac(id) else { return nil }
    if let record, let r = m.sessions.first(where: { $0.id == record }) {
      return EvidenceSource(mac: m, at: r.at ?? r.start, photos: r.photos.sorted(), events: r.timeline)
    }
    if let f = m.finished {
      return EvidenceSource(mac: m, at: f.at, photos: f.photos, events: f.events.sorted { $0.t < $1.t })
    }
    if m.alarmActive {
      let at = m.state.at ?? m.state.since
      let evs = m.state.events.filter { $0.t >= at - 2000 }.sorted { $0.t < $1.t }
      return EvidenceSource(mac: m, at: at, photos: m.alarmPhotos.sorted(), events: evs)
    }
    if let r = m.sessions.first(where: { $0.kind == .alarm }) {
      return EvidenceSource(mac: m, at: r.at ?? r.start, photos: r.photos.sorted(), events: r.timeline)
    }
    return nil
  }
}

/// The report itself, drawn in SwiftUI and rendered to a PDF. Light, plain, printable.
struct EvidenceDocument: View {
  var source: EvidenceSource
  var images: [UIImage]
  /// The preview in the sheet: smaller type, the first three photos, the first six lines.
  var compact = false

  private var scale: CGFloat { compact ? 0.62 : 1 }

  var body: some View {
    VStack(alignment: .leading, spacing: 10 * scale) {
      HStack(spacing: 8 * scale) {
        AppMark(size: 22 * scale)
        Text(t("evDocT")).font(.system(size: 20 * scale, weight: .bold))
      }
      Text("\(source.mac.name) · \(source.mac.model)\n\(Fmt.dateLong(source.at)) · \(Fmt.hms(source.at))")
        .font(.system(size: 13 * scale))
        .foregroundStyle(Color(hex: 0x555b6b))
      if !images.isEmpty {
        let shown = Array(images.prefix(compact ? 3 : 6))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6 * scale), count: 3), spacing: 6 * scale) {
          ForEach(Array(shown.enumerated()), id: \.offset) { _, image in
            Color.clear.aspectRatio(4 / 3, contentMode: .fit)
              .overlay { Image(uiImage: image).resizable().scaledToFill() }
              .clipShape(RoundedRectangle(cornerRadius: 4 * scale, style: .continuous))
          }
        }
      }
      VStack(alignment: .leading, spacing: 4 * scale) {
        ForEach(Array(source.events.prefix(compact ? 6 : source.events.count).enumerated()), id: \.offset) { _, e in
          Text("\(Fmt.hms(e.t))  \(EventText.text(e))")
            .font(.system(size: 13 * scale, design: .monospaced))
        }
      }
      Text("BRB · " + Fmt.dateLong(nowMs())).font(.system(size: 10 * scale)).foregroundStyle(Color(hex: 0x8a8f9c)).padding(.top, 6 * scale)
    }
    .foregroundStyle(Color(hex: 0x10131c))
    .padding(compact ? 14 : 32)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white)
    .environment(\.colorScheme, .light)
  }
}

struct PDFFile: FileDocument {
  static var readableContentTypes: [UTType] { [.pdf] }
  var data: Data

  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct EvidenceSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var macID: String
  var recordID: String?
  @State private var source: EvidenceSource?
  @State private var images: [UIImage] = []
  @State private var exporting = false
  @State private var pdf: PDFFile?
  @State private var item: ShareItem?

  var body: some View {
    VStack(spacing: 0) {
      SheetHeader(title: t("evT"), subtitle: t("evP")) { dismiss() }
        .padding(.bottom, 14)
      if let source {
        ScrollView {
          VStack(spacing: 14) {
            EvidenceDocument(source: source, images: images, compact: true)
              .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
              .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            Grp {
              EvidenceRow(title: t("ev_tl"), value: tn("ev_items", source.events.count))
              Hairline(inset: 14)
              EvidenceRow(title: t("ev_ph"), value: t("photosN", source.photos.count))
              Hairline(inset: 14)
              EvidenceRow(title: t("ev_vid"), value: t("ev_vidF"))
              Hairline(inset: 14)
              EvidenceRow(title: t("ev_blur"), value: t("ev_blurV"))
            }
          }
          .padding(.bottom, 8)
        }
        HStack(spacing: 10) {
          Button { exportFile() } label: {
            HStack(spacing: 7) {
              Image(systemName: "doc.text")
              Text(t("ev_files")).lineLimit(1).minimumScaleFactor(0.8)
            }
          }
          .buttonStyle(.big(.glass))
          Button { share() } label: {
            HStack(spacing: 7) {
              Image(systemName: "square.and.arrow.up")
              Text(t("ev_share")).lineLimit(1).minimumScaleFactor(0.8)
            }
          }
          .buttonStyle(.big(.tint))
        }
        .padding(.top, 10)
      } else {
        Spacer()
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 22)
    .padding(.bottom, 12)
    .presentationDetents([.large])
    .task {
      source = store.evidenceSource(mac: macID, record: recordID)
      if let source { images = await store.photoImages(of: source.mac, Array(source.photos.prefix(6))) }
    }
    .fileExporter(isPresented: $exporting, document: pdf, contentType: .pdf, defaultFilename: "BRB-alarm") { result in
      if case .success = result { store.show(t("ev_saved"), "doc.text") }
    }
    .sheet(item: $item) { it in ActivityView(items: it.items).presentationDetents([.medium, .large]) }
  }

  private func renderPDF() -> (Data, URL)? {
    guard let source else { return nil }
    let content = EvidenceDocument(source: source, images: images).frame(width: 595)
    let renderer = ImageRenderer(content: content)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("BRB-alarm-\(Fmt.hms(source.at).replacingOccurrences(of: ":", with: "-")).pdf")
    var written = false
    renderer.render { size, draw in
      var box = CGRect(origin: .zero, size: size)
      guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
      ctx.beginPDFPage(nil)
      draw(ctx)
      ctx.endPDFPage()
      ctx.closePDF()
      written = true
    }
    guard written, let data = try? Data(contentsOf: url) else { return nil }
    return (data, url)
  }

  private func exportFile() {
    guard let (data, _) = renderPDF() else { return }
    pdf = PDFFile(data: data)
    exporting = true
  }

  private func share() {
    guard let (_, url) = renderPDF() else { return }
    item = ShareItem(items: [url])
  }
}

struct EvidenceRow: View {
  var title: String
  var value: String
  var body: some View {
    HStack {
      Text(title).font(.system(size: 15.5, weight: .medium))
      Spacer()
      Text(value).font(.system(size: 15)).foregroundStyle(Theme.ink2).monospacedDigit()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
  }
}
