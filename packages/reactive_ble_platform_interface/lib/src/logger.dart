import 'model/log_level.dart';

abstract class Logger {
  set logLevel(LogLevel logLevel);
  LogLevel get logLevel;

  /// Verbose diagnostic log. Emitted only when [logLevel] is [LogLevel.verbose].
  void log(Object message);

  void info(Object message);

  void warning(Object message);

  void error(Object message, [Object? error, StackTrace? stackTrace]);
}
