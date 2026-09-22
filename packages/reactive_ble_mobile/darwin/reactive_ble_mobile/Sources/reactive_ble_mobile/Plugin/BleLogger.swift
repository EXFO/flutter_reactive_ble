#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif
import Foundation

enum BleLogger {
    static var eventSink: EventSink?

    static func info(_ source: String, _ message: String) {
        emit(source: source, level: "Info", message: message)
    }

    static func warning(_ source: String, _ message: String) {
        emit(source: source, level: "Warning", message: message)
    }

    static func error(_ source: String, _ message: String) {
        emit(source: source, level: "Error", message: message)
    }

    private static func emit(source: String, level: String, message: String) {
        eventSink?.addLog([
            "Level": level,
            "Source": source,
            "Message": message,
        ])
    }
}
