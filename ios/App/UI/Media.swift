import Photos
import SwiftUI
import UIKit

/// A photo from the relay, loaded once and kept in the cache.
struct RelayPhoto: View {
  @Environment(AppStore.self) private var store
  var mac: MacModel
  var ms: Ms
  @State private var image: UIImage?

  var body: some View {
    Color.clear
      .overlay {
        if let image {
          Image(uiImage: image).resizable().scaledToFill()
        } else {
          Rectangle().fill(Theme.skeleton)
        }
      }
      .clipped()
      .task(id: ms) {
        image = PhotoCache.shared.cached(ms, of: mac)
        if image == nil { image = await PhotoCache.shared.image(ms, of: mac, via: store.backend) }
      }
  }
}

/// The Mac's battery as the card shows it: the percentage and a small battery.
struct BatteryView: View {
  var pct: Int
  var charging: Bool

  var body: some View {
    HStack(spacing: 4) {
      if charging { Image(systemName: "bolt.fill").font(.system(size: 10)) }
      Text("\(pct)%").font(.system(size: 12.5)).monospacedDigit()
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 3.6, style: .continuous).stroke(Color.primary.opacity(0.45), lineWidth: 1)
          .frame(width: 22, height: 12)
        RoundedRectangle(cornerRadius: 2, style: .continuous)
          .frame(width: max(2, 17 * CGFloat(min(100, max(0, pct))) / 100), height: 8.6)
          .padding(.leading, 1.7)
      }
      .frame(width: 24, height: 12, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(pct)%")
  }
}

/// A line of the timeline: the time, the dot on its thread, what happened and, for a photo, the picture.
struct EventRow: View {
  var event: EventItem
  var mac: MacModel
  var first = false
  var last = false
  var size: CGFloat = 14.5

  private var tone: EventText.Tone { EventText.tone(event) }

  private var textColor: Color {
    switch tone {
    case .hot: return Theme.textRed
    case .clear: return Theme.textGreen
    default: return Theme.ink
    }
  }

  private var dotColor: Color {
    switch tone {
    case .hot: return Theme.red
    case .ok: return Theme.amber
    case .clear: return Theme.green
    case .plain: return Theme.ink3
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      Text(Fmt.hms(event.t))
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(Theme.ink3)
        .frame(width: 62, alignment: .leading)
      ZStack {
        VStack(spacing: 0) {
          Rectangle().fill(first ? Color.clear : Theme.hair).frame(width: 1)
          Rectangle().fill(last ? Color.clear : Theme.hair).frame(width: 1)
        }
        Circle().fill(dotColor).frame(width: 9, height: 9)
      }
      .frame(width: 14)
      Text(EventText.text(event))
        .font(.system(size: size))
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity, alignment: .leading)
      if event.e == "photo" {
        RelayPhoto(mac: mac, ms: event.t)
          .frame(width: 44, height: 33)
          .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      }
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
  }
}

/// A list of events, oldest at the top or newest at the top.
struct EventList: View {
  var events: [EventItem]
  var mac: MacModel
  var size: CGFloat = 14.5

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(events.enumerated()), id: \.element.id) { i, e in
        EventRow(event: e, mac: mac, first: i == 0, last: i == events.count - 1, size: size)
      }
    }
  }
}

enum PhotoExport {
  /// Adds the pictures to the camera roll. False when the owner said no.
  static func save(_ images: [UIImage]) async -> Bool {
    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    guard status == .authorized || status == .limited else { return false }
    do {
      try await PHPhotoLibrary.shared().performChanges {
        for image in images { PHAssetChangeRequest.creationRequestForAsset(from: image) }
      }
      return true
    } catch {
      return false
    }
  }
}

/// The system share sheet.
struct ActivityView: UIViewControllerRepresentable {
  var items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A shield, a few words and a button, for screens with nothing on them yet.
struct EmptyState<Art: View>: View {
  var title: String
  var message: String
  @ViewBuilder var art: Art
  var body: some View {
    VStack(spacing: 8) {
      art.padding(.bottom, 8)
      Text(title).font(.system(size: 21, weight: .bold)).multilineTextAlignment(.center)
      Text(message).font(.system(size: 15)).foregroundStyle(Theme.ink2).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 28)
    .padding(.top, 30)
    .frame(maxWidth: .infinity)
  }
}

/// The three little rows of cards in the "nothing here" art.
struct RecordsArt: View {
  var body: some View {
    VStack(spacing: 8) {
      ForEach(0..<3, id: \.self) { i in
        HStack(spacing: 10) {
          ShieldView(look: .idle, size: 22).foregroundStyle(Theme.tint)
          Capsule().fill(Theme.cardHi).frame(width: [64, 46, 54][i], height: 6)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 120, height: 24)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1))
        .opacity([1, 0.7, 0.45][i])
      }
    }
    .frame(height: 110)
  }
}

struct PairArt: View {
  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.card)
          .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.rim, lineWidth: 1.5))
          .overlay { ShieldView(look: .offline, size: 38).foregroundStyle(Theme.tint) }
          .frame(width: 118, height: 78)
        Capsule().fill(Theme.cardHi).frame(width: 142, height: 6).padding(.top, 4)
      }
      .offset(x: -14, y: -6)
      Image(systemName: "iphone.gen3")
        .font(.system(size: 52, weight: .light))
        .foregroundStyle(Theme.tint)
        .offset(x: 62, y: 18)
    }
    .frame(width: 180, height: 120)
  }
}
