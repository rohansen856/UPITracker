import 'package:flutter/services.dart';

class SmsService {
  static const _methodChannel = MethodChannel('com.example.receipt/methods');
  static const _eventChannel = EventChannel('com.example.receipt/sms');

  Stream<Map<String, dynamic>>? _smsStream;

  Future<List<Map<String, dynamic>>> readSmsHistory({
    int limit = 200,
    int? sinceTimestamp,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>(
        'readSmsHistory',
        {
          'limit': limit,
          'since': sinceTimestamp ?? 0,
        },
      );
      return result?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  Stream<Map<String, dynamic>> get incomingSmsStream {
    _smsStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _smsStream!;
  }
}
