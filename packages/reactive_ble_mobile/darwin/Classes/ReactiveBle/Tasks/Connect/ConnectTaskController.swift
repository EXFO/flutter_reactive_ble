import CoreBluetooth

/**
 * ConnectTaskController handles the connection lifecycle for a specific peripheral.
 *
 * Fix: This controller ensures robust state management during the connection process.
 * It prevents potential hangs and race conditions by:
 * 1. Validating that a connection attempt only initiates if the task is in a `.pending` state.
 * 2. Ensuring that connection updates are only processed when the task is actively in the `.connecting` phase.
 * 3. Handling cancellations gracefully by verifying the current state before interacting with the CBCentralManager.
 *
 * This strict state validation prevents inconsistent states that previously led to connection timeouts
 * or failed task completions.
 *
 * Pull request : https://github.com/PhilipsHue/flutter_reactive_ble/pull/902/changes#diff-6e64a9aa61c9dac7619e46bc8635750553a7fc0d3887734e174d380f05e96b1c
 */
struct ConnectTaskController: PeripheralTaskController {

    typealias TaskSpec = ConnectTaskSpec

    private let task: SubjectTask

    init(_ task: SubjectTask) {
        self.task = task
    }

    func connect(centralManager: CBCentralManager, peripheral: CBPeripheral) -> SubjectTask {
        guard case .pending = task.state else {
            return task.with(state: task.state.finished(.failedToConnect(
                NSError(domain: "ConnectTaskController", code: -1,
                       userInfo: [NSLocalizedDescriptionKey: "Invalid state for connect operation"]))))
        }

        centralManager.connect(peripheral)
        return task.with(state: task.state.processing(.connecting))
    }

    func handleConnectionChange(_ connectionChange: ConnectionChange) -> SubjectTask {
        guard case .processing(since: _, .connecting) = task.state else {
            return task.with(state: task.state.finished(.failedToConnect(
                NSError(domain: "ConnectTaskController", code: -2,
                       userInfo: [NSLocalizedDescriptionKey: "Invalid state for connection change"]))))
        }

        return task.with(state: task.state.finished(connectionChange))
    }

    func cancel(centralManager: CBCentralManager, peripheral: CBPeripheral, error: Error?) -> SubjectTask {
        switch task.state {
        case .pending:
            return task.with(state: task.state.finished(.failedToConnect(error)))
        case .processing(since: _, .connecting):
            centralManager.cancelPeripheralConnection(peripheral)
            return task.with(state: task.state.finished(.failedToConnect(error)))
        case .finished:
            return task.with(state: task.state.finished(.failedToConnect(
                NSError(domain: "ConnectTaskController", code: -3,
                       userInfo: [NSLocalizedDescriptionKey: "Cannot cancel already finished task"]))))
        }
    }
}