import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/transaction_record.dart';

void main() {
  group('TransactionType', () {
    test('fromValue returns correct enum for "debit"', () {
      expect(TransactionType.fromValue('debit'), TransactionType.debit);
    });

    test('fromValue returns correct enum for "credit"', () {
      expect(TransactionType.fromValue('credit'), TransactionType.credit);
    });

    test('fromValue defaults to debit for unknown string', () {
      expect(TransactionType.fromValue('unknown'), TransactionType.debit);
    });

    test('.value roundtrips correctly', () {
      expect(TransactionType.fromValue(TransactionType.debit.value), TransactionType.debit);
      expect(TransactionType.fromValue(TransactionType.credit.value), TransactionType.credit);
    });
  });

  group('TransactionRecord', () {
    late TransactionRecord record;
    final now = DateTime(2026, 4, 13, 10, 30);

    setUp(() {
      record = TransactionRecord(
        id: 'test-id-123',
        amount: 500.50,
        type: TransactionType.debit,
        upiApp: 'gpay',
        upiTransactionId: 'TXN123',
        bankReference: 'REF456',
        counterpartyName: 'John Doe',
        counterpartyUpiId: 'john@okaxis',
        accountInfo: '****1234',
        description: 'Test payment',
        note: 'Lunch',
        tags: 'food, restaurant',
        latitude: 28.6139,
        longitude: 77.2090,
        locationName: 'New Delhi',
        source: 'notification',
        rawText: 'Paid ₹500.50 to John Doe',
        dedupHash: 'abc123hash',
        transactionDate: now,
        synced: false,
        createdAt: now,
        updatedAt: now,
      );
    });

    test('toMap produces correct map', () {
      final map = record.toMap();
      expect(map['id'], 'test-id-123');
      expect(map['amount'], 500.50);
      expect(map['transaction_type'], 'debit');
      expect(map['upi_app'], 'gpay');
      expect(map['upi_transaction_id'], 'TXN123');
      expect(map['bank_reference'], 'REF456');
      expect(map['counterparty_name'], 'John Doe');
      expect(map['counterparty_upi_id'], 'john@okaxis');
      expect(map['account_info'], '****1234');
      expect(map['description'], 'Test payment');
      expect(map['note'], 'Lunch');
      expect(map['tags'], 'food, restaurant');
      expect(map['latitude'], 28.6139);
      expect(map['longitude'], 77.2090);
      expect(map['location_name'], 'New Delhi');
      expect(map['source'], 'notification');
      expect(map['raw_text'], 'Paid ₹500.50 to John Doe');
      expect(map['dedup_hash'], 'abc123hash');
      expect(map['synced'], 0);
      expect(map['transaction_date'], now.toIso8601String());
    });

    test('fromMap reconstructs record correctly', () {
      final map = record.toMap();
      final restored = TransactionRecord.fromMap(map);

      expect(restored.id, record.id);
      expect(restored.amount, record.amount);
      expect(restored.type, record.type);
      expect(restored.upiApp, record.upiApp);
      expect(restored.upiTransactionId, record.upiTransactionId);
      expect(restored.bankReference, record.bankReference);
      expect(restored.counterpartyName, record.counterpartyName);
      expect(restored.counterpartyUpiId, record.counterpartyUpiId);
      expect(restored.accountInfo, record.accountInfo);
      expect(restored.note, record.note);
      expect(restored.tags, record.tags);
      expect(restored.latitude, record.latitude);
      expect(restored.longitude, record.longitude);
      expect(restored.locationName, record.locationName);
      expect(restored.source, record.source);
      expect(restored.rawText, record.rawText);
      expect(restored.dedupHash, record.dedupHash);
      expect(restored.synced, record.synced);
    });

    test('fromMap handles synced=true (int 1)', () {
      final map = record.toMap();
      map['synced'] = 1;
      final restored = TransactionRecord.fromMap(map);
      expect(restored.synced, isTrue);
    });

    test('fromMap handles synced=true (bool)', () {
      final map = record.toMap();
      map['synced'] = true;
      final restored = TransactionRecord.fromMap(map);
      expect(restored.synced, isTrue);
    });

    test('fromMap handles null optional fields', () {
      final map = {
        'id': 'minimal',
        'amount': 100,
        'transaction_type': 'credit',
        'source': 'manual',
        'dedup_hash': 'hash123',
        'transaction_date': now.toIso8601String(),
        'synced': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      final restored = TransactionRecord.fromMap(map);
      expect(restored.id, 'minimal');
      expect(restored.amount, 100.0);
      expect(restored.type, TransactionType.credit);
      expect(restored.upiApp, isNull);
      expect(restored.counterpartyName, isNull);
      expect(restored.note, isNull);
      expect(restored.tags, '');
      expect(restored.latitude, isNull);
    });

    test('toMap -> fromMap roundtrip preserves all data', () {
      final roundtripped = TransactionRecord.fromMap(record.toMap());
      expect(roundtripped.toMap(), equals(record.toMap()));
    });

    group('copyWith', () {
      test('updates note only', () {
        final updated = record.copyWith(note: 'Dinner');
        expect(updated.note, 'Dinner');
        expect(updated.amount, record.amount);
        expect(updated.tags, record.tags);
      });

      test('updates tags only', () {
        final updated = record.copyWith(tags: 'dinner, expensive');
        expect(updated.tags, 'dinner, expensive');
        expect(updated.note, record.note);
      });

      test('updates synced status', () {
        final updated = record.copyWith(synced: true);
        expect(updated.synced, isTrue);
        expect(updated.id, record.id);
      });

      test('updates location fields', () {
        final updated = record.copyWith(
          latitude: 19.0760,
          longitude: 72.8777,
          locationName: 'Mumbai',
        );
        expect(updated.latitude, 19.0760);
        expect(updated.longitude, 72.8777);
        expect(updated.locationName, 'Mumbai');
      });

      test('preserves immutable fields', () {
        final updated = record.copyWith(note: 'Changed');
        expect(updated.id, record.id);
        expect(updated.amount, record.amount);
        expect(updated.type, record.type);
        expect(updated.dedupHash, record.dedupHash);
        expect(updated.transactionDate, record.transactionDate);
        expect(updated.source, record.source);
      });
    });

    group('tagList', () {
      test('splits comma-separated tags', () {
        expect(record.tagList, ['food', 'restaurant']);
      });

      test('returns empty list for empty tags', () {
        final r = record.copyWith(tags: '');
        expect(r.tagList, isEmpty);
      });

      test('trims whitespace from tags', () {
        final r = record.copyWith(tags: '  food , travel ,  ');
        expect(r.tagList, ['food', 'travel']);
      });

      test('filters out empty tags', () {
        final r = record.copyWith(tags: 'food,,travel,');
        expect(r.tagList, ['food', 'travel']);
      });
    });

    group('formattedAmount', () {
      test('formats with rupee symbol and 2 decimal places', () {
        expect(record.formattedAmount, '₹500.50');
      });

      test('formats whole number with .00', () {
        final r = TransactionRecord(
          id: 'x', amount: 100, type: TransactionType.debit,
          source: 'manual', dedupHash: 'h', transactionDate: now,
          createdAt: now, updatedAt: now,
        );
        expect(r.formattedAmount, '₹100.00');
      });
    });

    group('upiAppDisplayName', () {
      test('maps known apps correctly', () {
        final cases = {
          'gpay': 'Google Pay',
          'phonepe': 'PhonePe',
          'paytm': 'Paytm',
          'bhim': 'BHIM',
          'whatsapp': 'WhatsApp Pay',
          'amazon': 'Amazon Pay',
          'mobikwik': 'MobiKwik',
          'freecharge': 'Freecharge',
          'airtel': 'Airtel Payments',
          'jio': 'Jio Pay',
          'bank_sms': 'Bank SMS',
        };

        for (final entry in cases.entries) {
          final r = TransactionRecord(
            id: 'x', amount: 100, type: TransactionType.debit,
            upiApp: entry.key,
            source: 'manual', dedupHash: 'h', transactionDate: now,
            createdAt: now, updatedAt: now,
          );
          expect(r.upiAppDisplayName, entry.value, reason: 'Failed for ${entry.key}');
        }
      });

      test('returns raw app name for unknown apps', () {
        final r = TransactionRecord(
          id: 'x', amount: 100, type: TransactionType.debit,
          upiApp: 'somewallet',
          source: 'manual', dedupHash: 'h', transactionDate: now,
          createdAt: now, updatedAt: now,
        );
        expect(r.upiAppDisplayName, 'somewallet');
      });

      test('returns "Unknown" when upiApp is null', () {
        final r = TransactionRecord(
          id: 'x', amount: 100, type: TransactionType.debit,
          source: 'manual', dedupHash: 'h', transactionDate: now,
          createdAt: now, updatedAt: now,
        );
        expect(r.upiAppDisplayName, 'Unknown');
      });
    });
  });
}
