import XCTest
@testable import reactive_ble_mobile

final class PluginControllerEventBufferTests: XCTestCase {

    func testEventEmittedBeforeSinkIsFlushedAfterSinkReady() {
        let sut = PluginController()
        let bufferedEvent = DeviceInfo.with {
            $0.id = "test-device"
        }

        sut.emitOrBuffer(event: bufferedEvent)

        XCTAssertEqual(sut.pendingEvents.count, 1)
        XCTAssertFalse(sut.isEventSinkReady)

        var emittedEvents = 0
        let expectation = XCTestExpectation(description: "buffered event emitted")
        sut.eventSink = EventSink(name: "test") { _ in
            emittedEvents += 1
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(sut.isEventSinkReady)
        XCTAssertEqual(emittedEvents, 1)
        XCTAssertEqual(sut.pendingEvents.count, 0)
    }

    func testBufferedEventsAreBounded() {
        let sut = PluginController()

        (0..<1005).forEach { index in
            let event = DeviceInfo.with {
                $0.id = "test-device-\(index)"
            }
            sut.emitOrBuffer(event: event)
        }

        XCTAssertEqual(sut.pendingEvents.count, 1000)
        XCTAssertEqual(sut.pendingEvents.first?.id, "test-device-5")
        XCTAssertEqual(sut.pendingEvents.last?.id, "test-device-1004")
    }
}
