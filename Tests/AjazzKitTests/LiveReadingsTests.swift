import XCTest
@testable import AjazzKit

final class LiveReadingsTests: XCTestCase {

    func testCPUPercent() {
        // 30 busy ticks out of 100.
        XCTAssertEqual(LiveReadings.cpuPercent(from: [0, 0, 0, 0], to: [20, 5, 70, 5]), 30)
        XCTAssertNil(LiveReadings.cpuPercent(from: [1, 1, 1, 1], to: [1, 1, 1, 1]))
        // Counters wrap without crashing.
        XCTAssertEqual(LiveReadings.cpuPercent(from: [UInt32.max, 0, 0, 0], to: [9, 0, 10, 0]), 50)
    }

    func testClock() {
        let r = LiveReadings()
        let date = Date(timeIntervalSince1970: 0)
        let year = Calendar.current.component(.year, from: date)
        XCTAssertEqual(r.text(for: LiveText(source: .clock, value: "yyyy"), now: date), String(year))
        XCTAssertEqual(r.text(for: LiveText(source: .clock), now: date)?.count, 5)  // HH:mm
    }

    func testShellFirstLine() {
        XCTAssertEqual(LiveReadings.firstLine(of: "printf '\\n  hello  \\nworld\\n'"), "hello")
        XCTAssertEqual(LiveReadings.firstLine(of: "true"), "")
    }

    func testShellRunsInBackground() {
        let r = LiveReadings()
        let live = LiveText(source: .shell, value: "echo hi")
        XCTAssertNil(r.text(for: live))  // first call only starts it
        let done = expectation(description: "output arrives")
        func poll() {
            if r.text(for: live) == "hi" { done.fulfill() }
            else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll) }
        }
        poll()
        wait(for: [done], timeout: 5)
    }

    func testSystemReadingsDoNotCrash() {
        // Values depend on the machine; only the shape is checked.
        if let v = LiveReadings.volume() { XCTAssertTrue(v == "Muted" || v.hasSuffix("%")) }
        if let b = LiveReadings.battery() { XCTAssertTrue(b.hasSuffix("%")) }
    }
}
