import XCTest
@testable import reactive_ble_mobile

final class CentralThreadSafetyTests: XCTestCase {

    func testCompletedTaskCancelsScheduledTimeout() {
        let timeoutQueue = DispatchQueue(label: "test.timeout.queue")
        let registry = PeripheralTaskRegistry<TestTaskController>(timeoutQueue: timeoutQueue)
        let timeoutNotTriggered = expectation(description: "timeout should not trigger")
        timeoutNotTriggered.isInverted = true

        registry.registerTask(
            key: 1,
            params: .init(),
            timeout: (
                duration: 0.05,
                handler: {
                    timeoutNotTriggered.fulfill()
                }
            ),
            completion: { _ in }
        )

        registry.updateTask(key: 1) { $0.finish() }

        wait(for: [timeoutNotTriggered], timeout: 0.2)
    }
}

private struct TestTaskSpec: PeripheralTaskSpec {
    typealias Key = Int
    typealias Group = Int

    struct Params {}
    enum Stage {
        case running
    }

    typealias Result = String

    static let tag = "TEST"

    static func isMember(_ key: Key, of group: Group) -> Bool {
        key == group
    }
}

private struct TestTaskController: PeripheralTaskController {
    typealias TaskSpec = TestTaskSpec
    private let task: SubjectTask

    init(_ task: SubjectTask) {
        self.task = task
    }

    func finish() -> SubjectTask {
        task.with(state: task.state.finished("done"))
    }
}
