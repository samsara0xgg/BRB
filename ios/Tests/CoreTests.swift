import XCTest

final class CoreTests: XCTestCase {
  func testViewParsesAnAlarm() throws {
    let json = """
      {"v":3,"level":"owner","online":true,"offlineAt":null,"photos":[300,200,100],
       "state":{"v":3,"phase":"triggered","since":1000,"place":"cafe","note":"hi","vol":70,"test":false,"camera":true,
         "trigger":"lifted","at":5000,"siren":true,"stage":"siren","softEnd":null,"carried":true,"bumps":2,
         "mac":{"name":"Allen's MacBook Pro","model":"MacBook Pro 14″","batt":82,"chg":false},
         "health":{"ax":true,"cam":true,"lid":false,"mot":true},
         "events":[{"t":5000,"e":"triggered","k":"lifted"},{"t":5600,"e":"siren"}]}}
      """
    let view = try XCTUnwrap(RelayView(data: Data(json.utf8)))
    XCTAssertEqual(view.level, .owner)
    XCTAssertEqual(view.photos, [300, 200, 100])
    let snap = MacSnapshot(id: "a", name: "Mac", model: "m", view: view)
    XCTAssertEqual(snap.look, .alarm)
    XCTAssertEqual(snap.alarmPhase, .siren)
    XCTAssertEqual(snap.state.trigger, .lifted)
    XCTAssertEqual(snap.trigger, .lift)
    XCTAssertEqual(snap.state.mac?.batt, 82)
    XCTAssertEqual(snap.state.health.failing, ["lid"])
    XCTAssertEqual(snap.state.events.count, 2)
  }

  func testV2MacWithoutStage() throws {
    let soft = MacState(json: ["phase": "triggered", "siren": false, "trigger": "keyboard"])
    XCTAssertEqual(soft.effectiveStage, .soft)
    XCTAssertEqual(soft.trigger?.kind, .touch)
    let loud = MacState(json: ["phase": "triggered", "siren": true])
    XCTAssertEqual(loud.effectiveStage, .siren)
    XCTAssertNil(MacState(json: ["phase": "armed"]).effectiveStage)
  }

  func testLooks() {
    func look(_ state: [String: Any], online: Bool = true) -> Look {
      var v = RelayView()
      v.online = online
      v.state = MacState(json: state)
      return MacSnapshot(id: "a", name: "", model: "", view: v).look
    }
    XCTAssertEqual(look(["phase": "idle"]), .idle)
    XCTAssertEqual(look(["phase": "arming"]), .arming)
    XCTAssertEqual(look(["phase": "armed"]), .armed)
    XCTAssertEqual(look(["phase": "armed", "test": true]), .test)
    XCTAssertEqual(look(["phase": "armed", "health": ["cam": false]]), .partial)
    XCTAssertEqual(look(["phase": "armed", "health": ["lid": false]]), .armed)
    XCTAssertEqual(look(["phase": "armed"], online: false), .offline)
    XCTAssertEqual(look(["phase": "triggered", "stage": "soft"]), .warn)
    XCTAssertEqual(look(["phase": "triggered", "stage": "hushed"], online: false), .alarm)
  }

  func testCommandBodies() {
    let b = Command.start(place: .library, note: "back soon", test: false).body(id: "c1")
    XCTAssertEqual(b["k"] as? String, "start")
    XCTAssertEqual(b["place"] as? String, "library")
    XCTAssertEqual(b["note"] as? String, "back soon")
    XCTAssertEqual(b["test"] as? Bool, false)
    XCTAssertEqual(Command.disarm.body(id: "c2")["by"] as? String, "face")
    XCTAssertNil(Command.hush.body(id: "c3")["place"])
  }

  func testPairingCodes() {
    guard case .digits(let d)? = PairingCode.parse("123 456") else { return XCTFail("digits") }
    XCTAssertEqual(d, "123456")
    guard case .qr(let host, let code)? = PairingCode.parse("https://relay.example.workers.dev/pair/abcd2345efgh6789")
    else { return XCTFail("https") }
    XCTAssertEqual(host, "relay.example.workers.dev")
    XCTAssertEqual(code, "abcd2345efgh6789")
    guard case .qr(let h2, let c2)? = PairingCode.parse("brb://pair?c=abcd2345efgh6789&h=r.example.dev")
    else { return XCTFail("brb") }
    XCTAssertEqual(h2, "r.example.dev")
    XCTAssertEqual(c2, "abcd2345efgh6789")
    XCTAssertNil(PairingCode.parse("hello"))
    XCTAssertNil(PairingCode.parse("12345"))
  }

  func testSessionDecodesLeniently() throws {
    let json = #"{"id":"1","start":10,"end":20,"place":"nowhere","kind":"alarm","trigger":"trackpad","photos":[1,2],"events":[{"t":1,"e":"armed"}]}"#
    let s = try JSONDecoder().decode(SessionRecord.self, from: Data(json.utf8))
    XCTAssertEqual(s.place, .cafe)
    XCTAssertTrue(s.isAlarm)
    XCTAssertEqual(s.trigger, .trackpad)
    XCTAssertEqual(s.photos, [1, 2])
    XCTAssertEqual(s.duration, 10)
  }

  func testElapsedAndDuration() {
    XCTAssertEqual(Fmt.elapsed(0), "0:00")
    XCTAssertEqual(Fmt.elapsed(62_000), "1:02")
    XCTAssertEqual(Fmt.elapsed(3_723_000), "1:02:03")
  }
}
