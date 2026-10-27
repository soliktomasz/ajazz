import XCTest
@testable import AjazzKit

/// Logic only — nothing here changes the Mac's actual sound output.
final class AudioDevicesTests: XCTestCase {

    func testToggleTarget() {
        XCTAssertEqual(AudioDevices.toggleTarget(current: "phones", "phones", "speakers"), "speakers")
        XCTAssertEqual(AudioDevices.toggleTarget(current: "speakers", "phones", "speakers"), "phones")
        // Playing through something else: go to the first choice.
        XCTAssertEqual(AudioDevices.toggleTarget(current: "hdmi", "phones", "speakers"), "phones")
        XCTAssertEqual(AudioDevices.toggleTarget(current: nil, "phones", "speakers"), "phones")
    }

    func testCycleWraps() {
        let uids = ["a", "b", "c"]
        XCTAssertEqual(AudioDevices.cycled(uids, current: "a", by: 1), "b")
        XCTAssertEqual(AudioDevices.cycled(uids, current: "c", by: 1), "a")
        XCTAssertEqual(AudioDevices.cycled(uids, current: "a", by: -1), "c")
        XCTAssertEqual(AudioDevices.cycled(uids, current: "b", by: -4), "a")
        XCTAssertEqual(AudioDevices.cycled(uids, current: "gone", by: 1), "b")
        XCTAssertNil(AudioDevices.cycled([], current: nil, by: 1))
    }

    func testDefaultOutputIsListed() {
        let outputs = AudioDevices.outputs()
        XCTAssertEqual(Set(outputs.map(\.uid)).count, outputs.count)
        if let current = AudioDevices.defaultOutput() { XCTAssertTrue(outputs.contains(current)) }
    }

    func testArgsRoundTrip() throws {
        let action = Action(type: .task, value: "audio.toggleOutput", args: ["BuiltInSpeakerDevice", "X"])
        XCTAssertEqual(try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(action)), action)
        XCTAssertEqual(TaskLibrary.task("audio.toggleOutput")?.parameters.count, 2)
        XCTAssertEqual(TaskLibrary.task("audio.cycleOutputs")?.isDial, true)
    }
}
