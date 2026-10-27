import XCTest
@testable import AjazzKit

final class ConfigTests: XCTestCase {

    /// A config written before per-app pages and multi-actions still loads.
    func testOldConfigDecodes() throws {
        let json = #"{"brightness":80,"longPressSeconds":0.5,"pages":[{"name":"Main","keys":{"1":{"action":{"type":"launch","value":"Finder"}}}}]}"#
        let config = try JSONDecoder().decode(DeckConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.pages[0].apps, [])
        XCTAssertNil(config.pages[0].keys["1"]?.action?.steps)
    }

    func testMultiActionRoundTrips() throws {
        let multi = Action(type: .multi, steps: [
            Action(type: .hotkey, value: "cmd+c"),
            Action(type: .delay, value: "0.5"),
            Action(type: .page, value: "next"),
        ])
        let page = Page(name: "Code", keys: ["1": KeyConfig(action: multi)], apps: ["com.apple.dt.Xcode"])
        let data = try JSONEncoder().encode(DeckConfig(pages: [page]))
        XCTAssertEqual(try JSONDecoder().decode(DeckConfig.self, from: data).pages, [page])
    }

    func testPageForApp() {
        let pages = [Page(name: "Main"), Page(name: "Safari", apps: ["com.apple.Safari"])]
        XCTAssertEqual(DeckController.page(forApp: "com.apple.Safari", in: pages, fallback: 0), 1)
        XCTAssertEqual(DeckController.page(forApp: "com.apple.Terminal", in: pages, fallback: 0), 0)
    }
}

final class IdleConfigTests: XCTestCase {
    func testIdleMinutesIsOptional() throws {
        let json = #"{"brightness":80,"longPressSeconds":0.5,"pages":[]}"#
        XCTAssertNil(try JSONDecoder().decode(DeckConfig.self, from: Data(json.utf8)).idleMinutes)
        var c = DeckConfig(pages: []); c.idleMinutes = 10
        XCTAssertEqual(try JSONDecoder().decode(DeckConfig.self, from: JSONEncoder().encode(c)).idleMinutes, 10)
    }
}

final class ToggleTests: XCTestCase {
    func testSecondStateFallsBackToFirst() {
        var key = KeyConfig(label: "Mic", icon: "/tmp/mic.png", color: "#00ff00",
                            action: Action(type: .hotkey, value: "cmd+shift+m"))
        key.toggle = ToggleState(symbol: "mic.slash.fill")
        let second = key.toggled
        XCTAssertEqual(second.label, "Mic")
        XCTAssertEqual(second.color, "#00ff00")
        XCTAssertEqual(second.action, key.action)
        // The symbol must replace the first state's icon, which would otherwise win.
        XCTAssertNil(second.icon)
        XCTAssertEqual(second.symbol, "mic.slash.fill")
    }

    func testNoToggleIsIdentity() {
        let key = KeyConfig(label: "A")
        XCTAssertEqual(key.toggled, key)
    }
}

final class RearrangeTests: XCTestCase {
    func testSwapKeys() {
        var page = Page(name: "P", keys: ["1": KeyConfig(label: "A"), "2": KeyConfig(label: "B")])
        page.swapKeys(1, 2)
        XCTAssertEqual(page.keys["1"]?.label, "B")
        XCTAssertEqual(page.keys["2"]?.label, "A")
        page.swapKeys(1, 5)  // onto an empty slot: a move
        XCTAssertNil(page.keys["1"])
        XCTAssertEqual(page.keys["5"]?.label, "B")
    }
}
