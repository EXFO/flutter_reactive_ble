import 'package:logging/logging.dart' as logging;
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart';

class DebugLogger implements Logger {
  DebugLogger([String? source])
      : _logger = logging.Logger(
          (source == null || source.isEmpty)
              ? 'FlutterReactiveBle'
              : 'FlutterReactiveBle - $source',
        );

  final logging.Logger _logger;
  LogLevel _logLevel = LogLevel.none;

  @override
  set logLevel(LogLevel logLevel) => _logLevel = logLevel;

  @override
  LogLevel get logLevel => _logLevel;

  @override
  void log(Object message) {
    if (_logLevel != LogLevel.verbose) return;
    if (!_logger.isLoggable(logging.Level.FINE)) return;
    _logger.fine(message);
  }

  @override
  void info(Object message) {
    if (!_logger.isLoggable(logging.Level.INFO)) return;
    _logger.info(message);
  }

  @override
  void warning(Object message) {
    if (!_logger.isLoggable(logging.Level.WARNING)) return;
    _logger.warning(message);
  }

  @override
  void error(Object message, [Object? error, StackTrace? stackTrace]) {
    if (!_logger.isLoggable(logging.Level.SEVERE)) return;
    _logger.severe(message, error, stackTrace);
  }
}
