import SwiftUI

@main
struct BRBApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  @State private var store = AppStore.shared

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(store)
        .tint(Theme.tint)
        .onOpenURL { store.open(url: $0) }
    }
  }
}
