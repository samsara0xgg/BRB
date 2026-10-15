import Foundation

#if canImport(ActivityKit) && os(iOS)
  import ActivityKit

  /// The Live Activity for a guarded Mac. The relay's APNs updates carry the same content state as JSON,
  /// so the keys and their spelling are part of the protocol (relay/PROTOCOL.md).
  struct BRBActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
      /// armed, arming, partial, test, warn, alarm, back, hushed, clear, offline
      var look: String
      var place: String
      var since: Int64
      var armEnd: Int64
      var at: Int64
      var softEnd: Int64
      var bumps: Int
      var trigger: String?
      var photo: Int64
      var by: String?
      var test: Bool
      var pass: String?

      init(
        look: String, place: String = "cafe", since: Int64 = 0, armEnd: Int64 = 0, at: Int64 = 0, softEnd: Int64 = 0,
        bumps: Int = 0, trigger: String? = nil, photo: Int64 = 0, by: String? = nil, test: Bool = false, pass: String? = nil
      ) {
        self.look = look; self.place = place; self.since = since; self.armEnd = armEnd; self.at = at
        self.softEnd = softEnd; self.bumps = bumps; self.trigger = trigger; self.photo = photo; self.by = by
        self.test = test; self.pass = pass
      }

      init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        look = (try? c.decode(String.self, forKey: .look)) ?? "armed"
        place = (try? c.decode(String.self, forKey: .place)) ?? "cafe"
        since = (try? c.decode(Int64.self, forKey: .since)) ?? 0
        armEnd = (try? c.decode(Int64.self, forKey: .armEnd)) ?? 0
        at = (try? c.decode(Int64.self, forKey: .at)) ?? 0
        softEnd = (try? c.decode(Int64.self, forKey: .softEnd)) ?? 0
        bumps = (try? c.decode(Int.self, forKey: .bumps)) ?? 0
        trigger = try? c.decode(String.self, forKey: .trigger)
        photo = (try? c.decode(Int64.self, forKey: .photo)) ?? 0
        by = try? c.decode(String.self, forKey: .by)
        test = (try? c.decode(Bool.self, forKey: .test)) ?? false
        pass = try? c.decode(String.self, forKey: .pass)
      }
      private enum Keys: String, CodingKey {
        case look, place, since, armEnd, at, softEnd, bumps, trigger, photo, by, test, pass
      }
    }

    var macId: String
    var macName: String
  }

  extension MacSnapshot {
    /// The Live Activity's content for this Mac, or nil when there is nothing to show (idle).
    var activityState: BRBActivityAttributes.ContentState? {
      let s = state
      let lookName: String
      switch look {
      case .idle: return nil
      case .arming: lookName = "arming"
      case .armed: lookName = "armed"
      case .partial: lookName = "partial"
      case .test: lookName = "test"
      case .warn: lookName = "warn"
      case .offline: lookName = "offline"
      case .alarm:
        switch alarmPhase {
        case .returned: lookName = "back"
        case .muted: lookName = "hushed"
        default: lookName = "alarm"
        }
      }
      return BRBActivityAttributes.ContentState(
        look: lookName, place: s.place.rawValue, since: s.since, armEnd: s.armEnd ?? 0, at: s.at ?? 0,
        softEnd: s.softEnd ?? 0, bumps: s.bumps, trigger: s.trigger?.rawValue, photo: view.photos.first ?? 0, by: nil,
        test: s.test, pass: nil)
    }
  }
#endif
