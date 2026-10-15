import SwiftUI
import WidgetKit

/// Everything the widget extension offers: the home screen and Lock Screen widget, the Live Activity (Lock
/// Screen card and Dynamic Island), and on iOS 18 a control.
@main
struct BRBWidgetsBundle: WidgetBundle {
  var body: some Widget {
    BRBStatusWidget()
    BRBGuardActivity()
    if #available(iOS 18.0, *) {
      BRBGuardControl()
    }
  }
}
