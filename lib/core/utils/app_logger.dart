import 'package:flutter/foundation.dart';

/// Logger sederhana. Detail teknis hanya ke console, tidak ke UI.
class AppLogger {
  AppLogger._();

  static void d(String message) {
    if (kDebugMode) debugPrint('[D] $message');
  }

  static void i(String message) => debugPrint('[I] $message');

  static void e(String message, [Object? error, StackTrace? stack]) {
    debugPrint('[E] $message${error != null ? ' | $error' : ''}');
    if (stack != null && kDebugMode) debugPrint(stack.toString());
  }
}
