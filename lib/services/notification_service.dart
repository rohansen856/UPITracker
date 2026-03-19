import 'package:flutter/services.dart';

class NotificationService {
  static const _methodChannel = MethodChannel('com.example.receipt/methods');
  static const _eventChannel = EventChannel('com.example.receipt/notifications');

  Stream<Map<String, dynamic>>? _notificationStream;

  Future<bool> isNotificationAccessGranted() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isNotificationAccessGranted');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationAccessSettings() async {
    await _methodChannel.invokeMethod('openNotificationAccessSettings');
  }

  Stream<Map<String, dynamic>> get notificationStream {
    _notificationStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _notificationStream!;
  }
}
