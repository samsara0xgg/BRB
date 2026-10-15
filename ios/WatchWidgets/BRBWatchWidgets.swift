import SwiftUI
import WidgetKit

/// The Watch complication: the shield of the Mac that matters most right now, and a word. Tapping it opens the app.
struct WStatusWidget: Widget {
  let kind = "BRBWatchStatus"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: WWidgetProvider()) { entry in
      WWidgetView(entry: entry)
        .containerBackground(for: .widget) {
          Color.clear
        }
    }
    .configurationDisplayName(LocalizedStringKey(t("ww_widgetName")))
    .description(LocalizedStringKey(t("ww_widgetDesc")))
    .supportedFamilies([.accessoryCorner, .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

@main
struct BRBWatchWidgetsBundle: WidgetBundle {
  var body: some Widget {
    WStatusWidget()
  }
}
