import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Notifies listeners when the user double-taps the side of
/// an Apple Pencil (2nd generation or Pro) on iPadOS,
/// or squeezes an Apple Pencil Pro.
///
/// Taps are ignored if the user has turned off the double-tap action
/// in the iPadOS Apple Pencil settings.
abstract final class PencilDoubleTap {
  static final log = Logger('PencilDoubleTap');

  static const _channel = MethodChannel('saber/pencil_interaction');
  static final _listeners = <VoidCallback>[];
  static var _attached = false;

  static void addListener(VoidCallback listener) {
    _listeners.add(listener);
    _attach();
  }

  static void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  static void _attach() {
    if (_attached) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _attached = true;

    _channel.setMethodCallHandler(handleMethodCall);
    _channel.invokeMethod('attach').catchError((Object e) {
      log.warning('Failed to attach pencil interaction', e);
    });
  }

  /// Handles a message from the native side.
  @visibleForTesting
  static Future<void> handleMethodCall(MethodCall call) async {
    if (call.method != 'doubleTap') return;
    if (call.arguments == 'ignore') return;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
