import SwiftUI

struct RootView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    @Bindable var store = store
    ZStack {
      MainTabs()

      if let mac = store.mac(store.alarmMacID) {
        AlarmView(mac: mac)
          .transition(.asymmetric(insertion: .scale(scale: 0.2, anchor: .top).combined(with: .opacity), removal: .move(edge: .bottom)))
          .zIndex(5)
      }

      if store.onboarding != nil {
        OnboardingView()
          .transition(.move(edge: .bottom))
          .zIndex(6)
      }

      VStack {
        if let toast = store.toast {
          ToastView(spec: toast)
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 6)
        }
        Spacer()
      }
      .allowsHitTesting(false)
      .zIndex(10)
    }
    .animation(.spring(response: 0.55, dampingFraction: 0.82), value: store.alarmMacID)
    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: store.toast)
    .animation(.spring(response: 0.6, dampingFraction: 0.9), value: store.onboarding != nil)
    .sheet(item: $store.sheet) { sheet in
      SheetRouter(sheet: sheet)
        .environment(store)
        .presentationBackground(Theme.sheet)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
    }
    .alert(
      store.alert?.title ?? "", isPresented: Binding(get: { store.alert != nil }, set: { if !$0 { store.alert = nil } }),
      presenting: store.alert
    ) { spec in
      if spec.input != nil { TextField("", text: $store.alertInput) }
      ForEach(Array(spec.actions.enumerated()), id: \.offset) { _, a in
        Button(a.label, role: a.role) { a.run() }
      }
    } message: { spec in
      if let m = spec.message { Text(m) }
    }
    .task { store.bootstrap() }
    .onChange(of: scenePhase) { _, phase in store.scenePhase(active: phase == .active) }
    .preferredColorScheme(nil)
  }
}

struct MainTabs: View {
  @Environment(AppStore.self) private var store

  var body: some View {
    @Bindable var store = store
    TabView(selection: $store.tab) {
      NavigationStack(path: $store.devicesPath) {
        DevicesView().navigationDestinations()
      }
      .tabItem { Label(t("tabDevices"), systemImage: "shield") }
      .tag(Tab.devices)

      NavigationStack(path: $store.recordsPath) {
        RecordsView().navigationDestinations()
      }
      .tabItem { Label(t("tabRecords"), systemImage: "clock.arrow.circlepath") }
      .badge(store.recordsBadge ? "●" : nil)
      .tag(Tab.records)

      NavigationStack(path: $store.settingsPath) {
        SettingsView().navigationDestinations()
      }
      .tabItem { Label(t("tabSettings"), systemImage: "gearshape") }
      .tag(Tab.settings)
    }
    .onChange(of: store.tab) { _, tab in if tab == .records { store.recordsBadge = false } }
  }
}

extension View {
  func navigationDestinations() -> some View {
    navigationDestination(for: Route.self) { route in
      switch route {
      case .mac(let id): MacDetailView(macID: id)
      case .record(let mac, let id): RecordDetailView(macID: mac, recordID: id)
      case .privacy: PrivacyView()
      case .faq: FAQView()
      }
    }
  }
}

struct SheetRouter: View {
  @Environment(AppStore.self) private var store
  var sheet: Sheet

  var body: some View {
    switch sheet {
    case .start(let id):
      if let mac = store.mac(id) { StartSheet(mac: mac) }
    case .paywall:
      PaywallSheet()
    case .share(let id, let record):
      ShareSheet(macID: id, recordID: record)
    case .evidence(let id, let record):
      EvidenceSheet(macID: id, recordID: record)
    case .message:
      EmptyView()
    case .sendLink:
      SendLinkSheet()
    }
  }
}
