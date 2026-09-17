import Foundation

struct WriteWithoutResponseFlowControl {
    static let defaultWatchdogTimeoutMs = 500
    static let defaultMaxWatchdogRetries = 3

    private(set) var kickstarted = false
    private(set) var watchdogRetries = 0
    private(set) var queueDepth = 0

    mutating func enqueue() {
        queueDepth += 1
    }

    enum DrainAction: Equatable {
        case waitForReady
        case kickstart
        case send
        case idle
        case failHeadTimedOut
        case retryAfterWatchdog
    }

    mutating func nextDrainAction(canSend: Bool) -> DrainAction {
        guard queueDepth > 0 else {
            watchdogRetries = 0
            return .idle
        }
        if canSend {
            return .send
        }
        if !kickstarted {
            kickstarted = true
            return .kickstart
        }
        return .waitForReady
    }

    mutating func didSend() {
        precondition(queueDepth > 0)
        queueDepth -= 1
        if queueDepth == 0 {
            watchdogRetries = 0
        }
    }

    mutating func didBecomeReady() {
        watchdogRetries = 0
    }

    mutating func watchdogFired(canSend: Bool, maxRetries: Int = defaultMaxWatchdogRetries) -> DrainAction {
        guard queueDepth > 0 else { return .idle }
        watchdogRetries += 1
        if canSend || watchdogRetries <= maxRetries {
            return .retryAfterWatchdog
        }
        watchdogRetries = 0
        return .failHeadTimedOut
    }

    mutating func didFailHeadTimedOut() {
        precondition(queueDepth > 0)
        queueDepth -= 1
    }

    mutating func resetForNewConnection() {
        kickstarted = false
        watchdogRetries = 0
        queueDepth = 0
    }
}
