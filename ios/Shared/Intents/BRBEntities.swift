import AppIntents
import Foundation

/// A paired Mac, as Shortcuts, Siri and the widgets' buttons name it.
struct MacEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("wi_macType", defaultValue: "Mac", table: "Widgets"))
  static var defaultQuery = MacEntityQuery()

  var id: String
  var name: String

  init(id: String, name: String) {
    self.id = id
    self.name = name
  }

  init(_ mac: PairedMac) {
    self.id = mac.id
    self.name = mac.displayName
  }

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

struct MacEntityQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [MacEntity] {
    Library.macs().filter { identifiers.contains($0.id) }.map { MacEntity($0) }
  }

  func suggestedEntities() async throws -> [MacEntity] {
    Library.macs().map { MacEntity($0) }
  }
}

/// The three places a session can be started for.
enum PlaceChoice: String, AppEnum {
  case library, cafe, transit

  static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("shPlace", defaultValue: "Place"))

  static var caseDisplayRepresentations: [PlaceChoice: DisplayRepresentation] = [
    .library: DisplayRepresentation(title: LocalizedStringResource("pl_library", defaultValue: "Library")),
    .cafe: DisplayRepresentation(title: LocalizedStringResource("pl_cafe", defaultValue: "Café")),
    .transit: DisplayRepresentation(title: LocalizedStringResource("pl_road", defaultValue: "On the go")),
  ]

  var place: Place {
    switch self {
    case .library: return .library
    case .cafe: return .cafe
    case .transit: return .transit
    }
  }
}
