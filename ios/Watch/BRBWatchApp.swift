import SwiftUI

@main
struct BRBWatchApp: App {
  @StateObject private var model = WatchModel()
  @Environment(\.scenePhase) private var scenePhase

  init() {
    // Start listening for the iPhone's context as early as possible.
    WatchLink.shared.start()
  }

  var body: some Scene {
    WindowGroup {
      WRootView(model: model)
        .onChange(of: scenePhase, initial: true) { _, phase in
          model.sceneChanged(phase)
        }
    }
  }
}
