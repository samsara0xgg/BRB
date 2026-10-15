import AppIntents
import Foundation

/// What Siri, Spotlight and the Shortcuts app offer without any setup. The intents themselves are in
/// Shared/Intents; this provider must exist in the app target only.
///
/// The phrases are English. Localised phrases would go in AppShortcuts.strings (one per language).
struct BRBShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartGuardingIntent(),
      phrases: [
        "Start guarding with \(.applicationName)",
        "Guard my Mac with \(.applicationName)",
        "Start \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("wi_start_title", defaultValue: "Start guarding", table: "Widgets"),
      systemImageName: "shield.fill")

    AppShortcut(
      intent: StopGuardingIntent(),
      phrases: [
        "Stop guarding with \(.applicationName)",
        "Stop \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("wi_stop_title", defaultValue: "Stop guarding", table: "Widgets"),
      systemImageName: "hand.raised.fill")

    AppShortcut(
      intent: HushSirenIntent(),
      phrases: [
        "Stop the siren with \(.applicationName)",
        "Silence \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("wi_hush_title", defaultValue: "Stop the siren", table: "Widgets"),
      systemImageName: "speaker.slash.fill")

    AppShortcut(
      intent: GuardStatusIntent(),
      phrases: [
        "Is my Mac guarded in \(.applicationName)",
        "\(.applicationName) status",
      ],
      shortTitle: LocalizedStringResource("wi_status_title", defaultValue: "Get guard status", table: "Widgets"),
      systemImageName: "questionmark.circle")

    AppShortcut(
      intent: LatestSessionIntent(),
      phrases: [
        "Latest session in \(.applicationName)",
        "What happened to my Mac in \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("wi_latest_title", defaultValue: "Get the latest session", table: "Widgets"),
      systemImageName: "clock.arrow.circlepath")
  }
}
