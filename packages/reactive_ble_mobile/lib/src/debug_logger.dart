import 'package:logging/logging.dart' as logging;

/// Routes native BLE log events into [package:logging].
class DebugLogger {
  DebugLogger([String? source])
      : _logger = logging.Logger(
          (source == null || source.isEmpty)
              ? 'FlutterReactiveBle'
              : 'FlutterReactiveBle - $source',
        );

  final logging.Logger _logger;

  void info(Object message) {
    if (_logger.isLoggable(logging.Level.INFO)) {
      _logger.info(message);
    }
  }

  void warning(Object message) {
    if (_logger.isLoggable(logging.Level.WARNING)) {
      _logger.warning(message);
    }
  }

  void error(Object message) {
    if (_logger.isLoggable(logging.Level.SEVERE)) {
      _logger.severe(message);
    }
  }

  /// Handles payloads from the native `flutter_reactive_ble_log` EventChannel.
  static void log(dynamic event) {
    if (event is! Map) return;

    final message = event['Message']?.toString();
    if (message == null || message.isEmpty) return;

    final logger = DebugLogger(event['Source']?.toString());
    switch (event['Level']?.toString()) {
      case 'Warning':
        logger.warning(message);
        break;
      case 'Error':
        logger.error(message);
        break;
      default:
        logger.info(message);
        break;
    }
  }
}
