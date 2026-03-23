import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/services/sync_service.dart';

void main() {
  group('SyncResult', () {
    test('holds success data', () {
      final r = SyncResult(success: true, message: 'Synced 5 transactions', count: 5);
      expect(r.success, isTrue);
      expect(r.message, 'Synced 5 transactions');
      expect(r.count, 5);
    });

    test('holds failure data', () {
      final r = SyncResult(success: false, message: 'No internet connection');
      expect(r.success, isFalse);
      expect(r.count, 0);
    });

    test('count defaults to 0', () {
      final r = SyncResult(success: true, message: 'ok');
      expect(r.count, 0);
    });
  });
}
