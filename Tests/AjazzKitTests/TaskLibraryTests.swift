import XCTest
@testable import AjazzKit

final class TaskLibraryTests: XCTestCase {

    func testIDsAreUniqueAndScopedToTheirGroup() {
        XCTAssertEqual(Set(TaskLibrary.groups.map(\.id)).count, TaskLibrary.groups.count)
        let all = TaskLibrary.groups.flatMap(\.tasks)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        for group in TaskLibrary.groups {
            for task in group.tasks {
                XCTAssertTrue(task.id.hasPrefix(group.id + "."), task.id)
                XCTAssertNotNil(TaskLibrary.task(task.id))
            }
        }
    }

    /// A typo in a keystroke would otherwise only surface as a silent no-op.
    func testEveryKeystrokeParses() {
        for task in TaskLibrary.groups.flatMap(\.tasks) {
            switch task.effect {
            case .hotkey(let combo):
                XCTAssertNotNil(ActionRunner.parseHotkey(combo), "\(task.id): \(combo)")
            case .dial(let cw, let ccw):
                XCTAssertNotNil(ActionRunner.parseHotkey(cw), "\(task.id): \(cw)")
                XCTAssertNotNil(ActionRunner.parseHotkey(ccw), "\(task.id): \(ccw)")
            case .shell, .open, .appleScript, .custom, .customDial:
                break
            }
        }
    }

    func testEverySymbolExists() {
        for group in TaskLibrary.groups {
            XCTAssertTrue(KeySymbol(group.symbol).isValid, group.symbol)
            for task in group.tasks { XCTAssertTrue(KeySymbol(task.symbol).isValid, "\(task.id): \(task.symbol)") }
        }
    }

    func testOpenTargetsExist() {
        for task in TaskLibrary.groups.flatMap(\.tasks) {
            if case .open(let path) = task.effect, path.hasPrefix("/") {
                XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
            }
        }
    }

    func testHardwareKeyFlags() throws {
        let (up, upFlags) = try XCTUnwrap(ActionRunner.parseHotkey("ctrl+up"))
        XCTAssertEqual(up, 126)
        XCTAssertTrue(upFlags.isSuperset(of: [.maskControl, .maskSecondaryFn, .maskNumericPad]))
        XCTAssertTrue(try XCTUnwrap(ActionRunner.parseHotkey("f11")).1.contains(.maskSecondaryFn))
        let plain = try XCTUnwrap(ActionRunner.parseHotkey("cmd+m")).1
        XCTAssertEqual(plain, .maskCommand)
        XCTAssertNil(ActionRunner.parseHotkey("cmd+nosuchkey"))
    }

    func testTaskActionRoundTrips() throws {
        let action = Action(type: .task, value: "macos.lockScreen")
        let back = try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(back, action)
    }
}
