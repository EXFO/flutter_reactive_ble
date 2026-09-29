import CoreBluetooth
import Foundation

enum ErrorParser {

    static func code(for error: Error) -> ConnectionFailure {
        if let pluginError = error as? PluginError, case .connectionLost = pluginError {
            return .disconnectFromDevice
        }

        let nsError = error as NSError
        if nsError.domain == CBError.errorDomain || nsError.domain == "CBErrorDomain" {
            switch nsError.code {
            case CBError.Code.connectionTimeout.rawValue:
                return .timeout
            case CBError.Code.peripheralDisconnected.rawValue:
                return .disconnectFromDevice
            default:
                break
            }
        }

        return .failedToConnect
    }
}
