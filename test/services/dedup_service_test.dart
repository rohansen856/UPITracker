import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/transaction_record.dart';
import 'package:receipt/services/upi_parser.dart';
import 'package:receipt/services/dedup_service.dart';
import 'package:receipt/database/local_database.dart';

class FakeDedupLocalDatabase extends Fake implements LocalDatabase {
  final Set<String> _existingHashes = {};

  void addHash(String hash) => _existingHashes.add(hash);

  @override
  Future<bool> existsByDedupHash(String dedupHash) async {
    return _existingHashes.contains(dedupHash);
  }
}

void main() {
  late FakeDedupLocalDatabase fakeDb;
  late DedupService dedupService;

  setUp(() {
    fakeDb = FakeDedupLocalDatabase();
    dedupService = DedupService(fakeDb);
  });

  String md5Hash(String input) => md5.convert(utf8.encode(input)).toString();

  group('generateDedupHash', () {
    test('uses UPI transaction ID when available', () {
      final parsed = ParsedUpi(
        amount: 500,
        type: TransactionType.debit,
        upiTransactionId: 'TXN123ABC',
        bankReference: 'REF456',
        counterpartyName: 'John',
      );
      final timestamp = DateTime(2026, 4, 13, 10, 30);
      final hash = dedupService.generateDedupHash(parsed, timestamp);
      expect(hash, md5Hash('txn:TXN123ABC'));
    });

    test('falls back to bank reference when no txn ID', () {
      final parsed = ParsedUpi(
        amount: 500,
        type: TransactionType.debit,
        bankReference: 'REF456',
        counterpartyName: 'John',
      );
      final timestamp = DateTime(2026, 4, 13, 10, 30);
      final hash = dedupService.generateDedupHash(parsed, timestamp);
      expect(hash, md5Hash('ref:REF456'));
    });

    test('falls back to amount+time+counterparty when no IDs', () {
      final parsed = ParsedUpi(
        amount: 500.25,
        type: TransactionType.debit,
        counterpartyName: 'John Doe',
      );
      final timestamp = DateTime(2026, 4, 13, 10, 37);
      final hash = dedupService.generateDedupHash(parsed, timestamp);

      final roundedTime = DateTime(2026, 4, 13, 10, 30);
      final expected = md5Hash('amt:500.25|time:${roundedTime.toIso8601String()}|party:john doe');
      expect(hash, expected);
    });

    test('time rounding: minute 0-9 rounds to 0', () {
      final parsed = ParsedUpi(amount: 100, type: TransactionType.debit);
      final t1 = DateTime(2026, 4, 13, 10, 3);
      final t2 = DateTime(2026, 4, 13, 10, 9);
      expect(
        dedupService.generateDedupHash(parsed, t1),
        dedupService.generateDedupHash(parsed, t2),
      );
    });

    test('time rounding: minute 10-19 rounds to 10', () {
      final parsed = ParsedUpi(amount: 100, type: TransactionType.debit);
      final t1 = DateTime(2026, 4, 13, 10, 10);
      final t2 = DateTime(2026, 4, 13, 10, 19);
      expect(
        dedupService.generateDedupHash(parsed, t1),
        dedupService.generateDedupHash(parsed, t2),
      );
    });

    test('different 10-minute windows produce different hashes', () {
      final parsed = ParsedUpi(amount: 100, type: TransactionType.debit);
      final t1 = DateTime(2026, 4, 13, 10, 5);
      final t2 = DateTime(2026, 4, 13, 10, 15);
      expect(
        dedupService.generateDedupHash(parsed, t1),
        isNot(dedupService.generateDedupHash(parsed, t2)),
      );
    });

    test('counterparty name is lowercased and trimmed', () {
      final p1 = ParsedUpi(amount: 100, type: TransactionType.debit, counterpartyName: '  JOHN DOE  ');
      final p2 = ParsedUpi(amount: 100, type: TransactionType.debit, counterpartyName: 'john doe');
      final ts = DateTime(2026, 4, 13, 10, 5);
      expect(
        dedupService.generateDedupHash(p1, ts),
        dedupService.generateDedupHash(p2, ts),
      );
    });

    test('uses UPI ID as counterparty fallback', () {
      final parsed = ParsedUpi(
        amount: 100,
        type: TransactionType.debit,
        counterpartyUpiId: 'john@okaxis',
      );
      final ts = DateTime(2026, 4, 13, 10, 5);
      final hash = dedupService.generateDedupHash(parsed, ts);

      final roundedTime = DateTime(2026, 4, 13, 10, 0);
      final expected = md5Hash('amt:100.00|time:${roundedTime.toIso8601String()}|party:john@okaxis');
      expect(hash, expected);
    });

    test('empty txn ID falls through to bank reference', () {
      final parsed = ParsedUpi(
        amount: 100,
        type: TransactionType.debit,
        upiTransactionId: '',
        bankReference: 'REF789',
      );
      final ts = DateTime(2026, 4, 13, 10, 5);
      final hash = dedupService.generateDedupHash(parsed, ts);
      expect(hash, md5Hash('ref:REF789'));
    });

    test('empty bank reference falls through to time-based hash', () {
      final parsed = ParsedUpi(
        amount: 100,
        type: TransactionType.debit,
        upiTransactionId: '',
        bankReference: '',
        counterpartyName: 'Test',
      );
      final ts = DateTime(2026, 4, 13, 10, 5);
      final hash = dedupService.generateDedupHash(parsed, ts);

      final roundedTime = DateTime(2026, 4, 13, 10, 0);
      final expected = md5Hash('amt:100.00|time:${roundedTime.toIso8601String()}|party:test');
      expect(hash, expected);
    });

    test('same SMS from two senders produces same hash via ref', () {
      final p1 = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969',
      );
      final p2 = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969',
      );
      final ts = DateTime(2026, 4, 12, 14, 0);

      expect(
        dedupService.generateDedupHash(p1, ts),
        dedupService.generateDedupHash(p2, ts),
      );
    });
  });

  group('isDuplicate', () {
    test('returns true when hash exists in DB', () async {
      fakeDb.addHash('hash123');
      expect(await dedupService.isDuplicate('hash123'), isTrue);
    });

    test('returns false when hash does not exist in DB', () async {
      expect(await dedupService.isDuplicate('hash456'), isFalse);
    });
  });
}
