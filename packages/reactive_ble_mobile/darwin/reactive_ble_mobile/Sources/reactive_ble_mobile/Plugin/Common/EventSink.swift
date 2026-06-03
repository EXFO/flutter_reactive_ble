#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

import Foundation
import enum SwiftProtobuf.BinaryEncodingError

struct EventSink {

    private let name: String
    private let sink: FlutterEventSink

    init(name: String, _ sink: @escaping FlutterEventSink) {
        self.name = name
        self.sink = sink
    }

    private func emitOnMain(_ value: Any?) {
        if Thread.isMainThread {
            sink(value)
            return
        }

        DispatchQueue.main.async {
            sink(value)
        }
    }

    func add(_ event: PlatformMethodResult) {
        switch event {
        case .success(let message):
            if let message = message {
                do {
                    emitOnMain(FlutterStandardTypedData(bytes: try message.serializedData()))
                } catch let error as BinaryEncodingError {
                    emitOnMain(
                        PluginError.messageSerializationFailure(
                            type: type(of: message),
                            underlyingError: error
                        ).asFlutterError
                    )
                } catch {
                    emitOnMain(PluginError.unknown(error).asFlutterError)
                }
            } else {
                emitOnMain(nil)
            }
        case .failure(let error):
            emitOnMain(error)
        }
    }
}
