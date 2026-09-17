import XCTest
@testable import reactive_ble_mobile

final class WriteWithoutResponseFlowControlTests: XCTestCase {

    func testFifoDrainOnlyWhenCanSend() {
        var sut = WriteWithoutResponseFlowControl()
        sut.enqueue()
        sut.enqueue()

        XCTAssertEqual(sut.nextDrainAction(canSend: false), .kickstart)
        sut.didSend()
        XCTAssertEqual(sut.nextDrainAction(canSend: false), .waitForReady)
        XCTAssertEqual(sut.nextDrainAction(canSend: true), .send)
        sut.didSend()
        XCTAssertEqual(sut.nextDrainAction(canSend: true), .idle)
    }

    func testKickstartOnlyOncePerConnection() {
        var sut = WriteWithoutResponseFlowControl()
        sut.enqueue()
        XCTAssertEqual(sut.nextDrainAction(canSend: false), .kickstart)
        sut.didSend()
        sut.enqueue()
        XCTAssertEqual(sut.nextDrainAction(canSend: false), .waitForReady)

        sut.resetForNewConnection()
        sut.enqueue()
        XCTAssertEqual(sut.nextDrainAction(canSend: false), .kickstart)
    }

    func testWatchdogRetriesThenTimesOut() {
        var sut = WriteWithoutResponseFlowControl()
        sut.enqueue()
        _ = sut.nextDrainAction(canSend: false) // kickstart
        sut.didSend()
        sut.enqueue()
        XCTAssertEqual(sut.nextDrainAction(canSend: false), .waitForReady)

        XCTAssertEqual(sut.watchdogFired(canSend: false, maxRetries: 3), .retryAfterWatchdog)
        XCTAssertEqual(sut.watchdogFired(canSend: false, maxRetries: 3), .retryAfterWatchdog)
        XCTAssertEqual(sut.watchdogFired(canSend: false, maxRetries: 3), .retryAfterWatchdog)
        XCTAssertEqual(sut.watchdogFired(canSend: false, maxRetries: 3), .failHeadTimedOut)
        sut.didFailHeadTimedOut()
        XCTAssertEqual(sut.nextDrainAction(canSend: true), .idle)
    }

    func testReadyResetsWatchdogRetries() {
        var sut = WriteWithoutResponseFlowControl()
        sut.enqueue()
        _ = sut.nextDrainAction(canSend: false)
        sut.didSend()
        sut.enqueue()
        _ = sut.watchdogFired(canSend: false, maxRetries: 3)
        _ = sut.watchdogFired(canSend: false, maxRetries: 3)
        sut.didBecomeReady()
        XCTAssertEqual(sut.watchdogRetries, 0)
    }
}
