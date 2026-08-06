import Foundation

final class PeripheralTaskRegistry<Controller: PeripheralTaskController> {

    typealias SubjectTask = Controller.SubjectTask
    typealias TaskCompletionHandler = (SubjectTask.Key, SubjectTask.Params, SubjectTask.Result) -> Void

    private var tasks = TaskQueue()
    private var scheduledTimeouts = [TaskQueue.Record.UniqueID: DispatchWorkItem]()
    private let timeoutQueue: DispatchQueue
    private let queueSpecificKey = DispatchSpecificKey<UInt8>()
    private let queueSpecificValue: UInt8 = 1

    init(timeoutQueue: DispatchQueue = .main) {
        self.timeoutQueue = timeoutQueue
        timeoutQueue.setSpecific(key: queueSpecificKey, value: queueSpecificValue)
    }

    func registerTask(
        key: SubjectTask.Key,
        params: SubjectTask.Params,
        timeout: SubjectTask.Timeout? = nil,
        completion: @escaping SubjectTask.CompletionHandler
    ) {
        performSync {
            let task = SubjectTask(
                key: key,
                params: params,
                timeout: timeout,
                completion: completion
            )
            tasks.add(task)
        }
    }

    func updateTask(
        key: SubjectTask.Key,
        action: (Controller) -> SubjectTask
    ) {
        performSync {
            guard let record = tasks.firstWith(key: key)
            else { return }

            applyTaskUpdate(
                record: record,
                updatedTask: action(Controller(record.task)),
                scheduleTimeoutOnStart: true
            )
        }
    }

    func updateTasks(
        in group: SubjectTask.Group,
        action: (Controller) -> SubjectTask
    ) {
        performSync {
            let matching = tasks.records(where: { $0.isMember(of: group) })
            matching.forEach { record in
                applyTaskUpdate(
                    record: record,
                    updatedTask: action(Controller(record.task)),
                    scheduleTimeoutOnStart: false
                )
            }
        }
    }

    func clearAll() {
        performSync {
            scheduledTimeouts.values.forEach { $0.cancel() }
            scheduledTimeouts.removeAll()
            tasks.removeAll()
        }
    }

    private func applyTaskUpdate(
        record: TaskQueue.Record,
        updatedTask: SubjectTask,
        scheduleTimeoutOnStart: Bool
    ) {
        updatedTask.iif(
            finished: { _, result in
                finishTask(
                    uniqueID: record.uniqueID,
                    result: result,
                    completion: updatedTask.completion
                )
            },
            otherwise: {
                tasks.update(record.with(task: updatedTask))
                if scheduleTimeoutOnStart,
                   case .pending = record.task.state,
                   case .processing = updatedTask.state,
                   let timeout = record.task.timeout {
                    scheduleTaskTimeout(record.uniqueID, timeout)
                }
            }
        )
    }

    private func finishTask(
        uniqueID: TaskQueue.Record.UniqueID,
        result: SubjectTask.Result,
        completion: SubjectTask.CompletionHandler
    ) {
        guard tasks.firstWith(uniqueID: uniqueID) != nil else {
            return
        }

        clearTimeout(uniqueID)
        tasks.remove(uniqueID)
        completion(result)
    }

    private func clearTimeout(_ uniqueID: TaskQueue.Record.UniqueID) {
        if let timeoutWorkItem = scheduledTimeouts.removeValue(forKey: uniqueID) {
            timeoutWorkItem.cancel()
        }
    }

    private func scheduleTaskTimeout(_ uniqueID: TaskQueue.Record.UniqueID, _ timeout: SubjectTask.Timeout) {
        clearTimeout(uniqueID)

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.handleTimeout(uniqueID: uniqueID, timeout: timeout)
        }

        scheduledTimeouts[uniqueID] = timeoutWorkItem
        timeoutQueue.asyncAfter(deadline: .now() + timeout.duration, execute: timeoutWorkItem)
    }

    private func handleTimeout(uniqueID: TaskQueue.Record.UniqueID, timeout: SubjectTask.Timeout) {
        performSync {
            guard scheduledTimeouts.removeValue(forKey: uniqueID) != nil else {
                return
            }
            guard tasks.firstWith(uniqueID: uniqueID) != nil else {
                return
            }

            timeout.handler()
        }
    }

    private func performSync(_ operation: () -> Void) {
        if DispatchQueue.getSpecific(key: queueSpecificKey) == queueSpecificValue {
            operation()
            return
        }

        timeoutQueue.sync(execute: operation)
    }

    private class TaskQueue {

        private let counter = Counter()
        private var records = [Record]()

        func add(_ task: SubjectTask) {
            records.append(Record(
                uniqueID: counter.increment(),
                task: task
            ))
        }

        func firstWith(key: SubjectTask.Key) -> Record? {
            return records.first(where: { $0.task.key == key })
        }

        func firstWith(uniqueID: Record.UniqueID) -> Record? {
            return records.first(where: { $0.uniqueID == uniqueID })
        }

        func records(where p: (SubjectTask) -> Bool) -> [Record] {
            records.filter { p($0.task) }
        }

        func update(_ record: Record) {
            guard let index = records.firstIndex(where: { $0.uniqueID == record.uniqueID })
            else { return }

            records[index] = record
        }

        func remove(_ uniqueID: Record.UniqueID) {
            guard let index = records.firstIndex(where: { $0.uniqueID == uniqueID })
            else { return }

            records.remove(at: index)
        }

        func removeAll() {
            records.removeAll()
        }

        struct Record {

            typealias UniqueID = Int

            let uniqueID: UniqueID
            let task: SubjectTask

            func with(task: SubjectTask) -> Record {
                return .init(uniqueID: uniqueID, task: task)
            }
        }
    }

    private class Counter {

        private(set) var value = 0

        func increment() -> Int {
            value += 1
            return value
        }
    }
}
