enum ConnectionFailure: Int {

    case unknown
    case failedToConnect
}

enum ClearGattCacheFailure: Int {

    case operationNotSupported = 1
}

enum CharacteristicValueUpdateFailure: Int {

    case unknown
}

enum WriteCharacteristicFailure: Int {

    case unknown = 0
    case timedOut = 1
}

enum BleWriteError: Error, CustomStringConvertible {
    case writeWithoutResponseTimedOut

    var description: String {
        switch self {
        case .writeWithoutResponseTimedOut:
            return "writeCharacteristicWithoutResponse timed out waiting for peripheralIsReady(toSendWriteWithoutResponse:)"
        }
    }
}

enum MaximumWriteValueLengthRetrieval: Int {

    case unknown
}

enum RequestConnectionPriorityFailure: Int {

    case operationNotSupported = 1
}
