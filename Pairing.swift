import Foundation

/// The pairing code for the iPhone app, behind Settings → Phone → "Pair iPhone…". The relay makes a
/// code that lives 10 minutes and works once; this renews it before it runs out while the pane is
/// open, and holds the Mac's relay socket open for as long as the code is good, because the phone's
/// claim arrives on that socket. Closing the pane stops the renewing, not the listening: a phone that
/// scans the code in its last minutes still gets through.
final class PairingModel: ObservableObject {
  /// The code on show, or nil.
  @Published private(set) var offer: PairOffer?
  /// Seconds left on `offer`.
  @Published private(set) var remaining = 0
  /// The relay could not be reached for a first code.
  @Published private(set) var failed = false
  /// A code is good, so the Mac listens on the relay for the phone that claims it.
  @Published private(set) var watching = false
  /// The pane is showing the code (as opposed to just listening for it).
  @Published private(set) var shown = false
  /// "Unpair all phones…" asks first, and folds back by itself.
  @Published var confirmUnpair = false

  /// The listening started or stopped: the app opens or closes the socket.
  var onWatch: (Bool) -> Void = { _ in }
  private var busy = false
  private var nextTry = Date.distantPast
  private var timer: Timer?
  private var unpairAsk = 0

  /// The pane shows the code: a fresh one unless the one in hand still has over half a minute.
  func begin() {
    shown = true
    failed = false
    if let offer, offer.expires.timeIntervalSinceNow > 30 {
      remaining = seconds(offer)
    } else {
      fetch()
    }
    startTimer()
  }

  /// The pane is gone: no more renewing. The current code stays good, and heard for, until it runs out.
  func end() {
    shown = false
    confirmUnpair = false
    if !watching { stopTimer() }
  }

  /// A phone claimed the code (it is spent), or the room was reset (it belonged to the old one).
  func finish() {
    offer = nil
    failed = false
    setWatching(false)
    if !shown { stopTimer() }
  }

  func askUnpair() {
    confirmUnpair = true
    unpairAsk += 1
    let ask = unpairAsk
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let self, confirmUnpair, unpairAsk == ask else { return }
      confirmUnpair = false
    }
  }

  func cancelUnpair() {
    confirmUnpair = false
  }

  /// A new key and token: every phone holds the old token, and the page link changes with it.
  func unpair() {
    confirmUnpair = false
    Live.resetLink()
  }

  private func seconds(_ offer: PairOffer) -> Int {
    max(0, Int(offer.expires.timeIntervalSinceNow.rounded(.up)))
  }

  private func fetch() {
    guard !busy else { return }
    busy = true
    Live.pairOffer { [weak self] result in
      guard let self else { return }
      busy = false
      switch result {
      case .success(let new):
        offer = new
        failed = false
        remaining = seconds(new)
        setWatching(true)
      case .failure:
        failed = offer == nil  // a code that still works stays on show
        nextTry = Date().addingTimeInterval(5)
      }
    }
  }

  private func setWatching(_ on: Bool) {
    guard watching != on else { return }
    watching = on
    onWatch(on)
  }

  private func startTimer() {
    guard timer == nil else { return }
    let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func tick() {
    guard let offer else {
      if shown, failed, Date() >= nextTry { fetch() }
      if !shown, !watching { stopTimer() }
      return
    }
    remaining = seconds(offer)
    if remaining == 0 {
      self.offer = nil
      setWatching(false)
      if shown { fetch() } else { stopTimer() }  // the pane is still open: the next code follows
    } else if shown, remaining <= 30, Date() >= nextTry {
      fetch()
    }
  }
}
