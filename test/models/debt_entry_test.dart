import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/debt_entry.dart';

void main() {
  final t0 = DateTime(2026, 10, 1, 9);
  final t1 = DateTime(2026, 10, 2, 9);

  DebtEntry settledEntry() => DebtEntry(
        id: 'd1',
        direction: DebtDirection.owedToMe,
        counterparty: 'Asha',
        amount: 250,
        createdAt: t0,
        settled: true,
        settledAt: t1,
        updatedAt: t1,
      );

  group('DebtEntry.copyWith settledAt', () {
    test('passing settledAt: null keeps the existing value', () {
      final e = settledEntry().copyWith(settledAt: null);
      expect(e.settledAt, t1);
    });

    test('clearSettledAt removes the timestamp when un-settling', () {
      final e = settledEntry().copyWith(settled: false, clearSettledAt: true);
      expect(e.settled, isFalse);
      expect(e.settledAt, isNull);
      expect(e.toMap()['settled_at'], isNull);
    });
  });
}
