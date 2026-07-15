import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/transaction_record.dart';
import 'package:receipt/services/upi_parser.dart';
import 'package:receipt/services/dedup_service.dart';
import 'package:receipt/database/local_database.dart';

class FakeDedupLocalDatabase extends Fake implements LocalDatabase {
  final List<TransactionRecord> records = [];

  @override
  Future<bool> existsByDedupHash(String dedupHash) async {
    return records.any((r) => r.dedupHash == dedupHash);
  }

  @override
  Future<List<TransactionRecord>> findDedupCandidates({
    required double amount,
    required String type,
    required DateTime from,
    required DateTime to,
  }) async {
    return records
        .where((r) =>
            r.amount == amount &&
            r.type.value == type &&
            !r.transactionDate.isBefore(from) &&
            !r.transactionDate.isAfter(to))
        .toList();
  }
}

void main() {
  late FakeDedupLocalDatabase fakeDb;
  late DedupService dedupService;
  var recordId = 0;

  setUp(() {
    fakeDb = FakeDedupLocalDatabase();
    dedupService = DedupService(fakeDb);
  });

  String md5Hash(String input) => md5.convert(utf8.encode(input)).toString();

  /// Inserts a captured message the way the provider does.
  void insertSms(String body, DateTime ts, {String sender = 'JD-TEST-S'}) {
    final parsed = UpiParser.parseSms(sender: sender, body: body);
    fakeDb.records.add(TransactionRecord(
      id: 'r${recordId++}',
      amount: parsed.amount!,
      type: parsed.type!,
      upiTransactionId: parsed.upiTransactionId,
      bankReference: parsed.bankReference,
      counterpartyName: parsed.counterpartyName,
      counterpartyUpiId: parsed.counterpartyUpiId,
      source: 'sms',
      rawText: body,
      dedupHash: dedupService.generateDedupHash(parsed, body),
      transactionDate: ts,
      createdAt: ts,
      updatedAt: ts,
    ));
  }

  /// Runs the full dedup check for an incoming message.
  Future<bool> isDup(String body, DateTime ts, {String sender = 'VA-TEST-S'}) {
    final parsed = UpiParser.parseSms(sender: sender, body: body);
    final hash = dedupService.generateDedupHash(parsed, body);
    return dedupService.isDuplicate(parsed, ts, hash);
  }

  group('generateDedupHash', () {
    test('uses UPI transaction ID when available', () {
      final parsed = ParsedUpi(
        amount: 500,
        type: TransactionType.debit,
        upiTransactionId: 'TXN123ABC',
        bankReference: 'REF456',
        counterpartyName: 'John',
      );
      expect(dedupService.generateDedupHash(parsed, 'raw'), md5Hash('txn:TXN123ABC'));
    });

    test('falls back to bank reference when no txn ID', () {
      final parsed = ParsedUpi(
        amount: 500,
        type: TransactionType.debit,
        bankReference: 'REF456',
      );
      expect(dedupService.generateDedupHash(parsed, 'raw'), md5Hash('ref:REF456'));
    });

    test('empty txn ID falls through to bank reference', () {
      final parsed = ParsedUpi(
        amount: 100,
        type: TransactionType.debit,
        upiTransactionId: '',
        bankReference: 'REF789',
      );
      expect(dedupService.generateDedupHash(parsed, 'raw'), md5Hash('ref:REF789'));
    });

    test('without ids, hashes the normalized message body', () {
      final parsed = ParsedUpi(amount: 100, type: TransactionType.debit);
      expect(
        dedupService.generateDedupHash(parsed, "You've paid Rs. 100 via PhonePe wallet."),
        md5Hash("body:you've paid rs. 100 via phonepe wallet."),
      );
    });

    test('body hash is whitespace- and case-insensitive', () {
      final parsed = ParsedUpi(amount: 100, type: TransactionType.debit);
      expect(
        dedupService.generateDedupHash(parsed, "You've paid Rs.  100  via PhonePe wallet."),
        dedupService.generateDedupHash(parsed, "you've paid rs. 100 via phonepe wallet."),
      );
    });

    test('same ref-bearing SMS from two senders produces same hash', () {
      const body =
          'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969';
      final p1 = UpiParser.parseSms(sender: 'JD-SBIUPI-S', body: body);
      final p2 = UpiParser.parseSms(sender: 'VA-SBIUPI-S', body: body);
      expect(
        dedupService.generateDedupHash(p1, body),
        dedupService.generateDedupHash(p2, body),
      );
    });
  });

  group('PhonePe wallet payments (no ref, no counterparty)', () {
    // Real scenario from the user's inbox: four Rs.1000 wallet payments
    // within two minutes, distinguishable only by the remaining balance.
    const wallet4000 =
        "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 4000. To top-up click https://phone.pe/PHONPE/ws";
    const wallet3000 =
        "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 3000. To top-up click https://phone.pe/PHONPE/ws";
    const wallet1000 =
        "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 1000. To top-up click https://phone.pe/PHONPE/ws";
    const wallet0 =
        "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 0. To top-up click https://phone.pe/PHONPE/ws";

    test('consecutive identical payments with different balances are distinct', () async {
      final t = DateTime(2026, 7, 14, 22, 58);
      insertSms(wallet4000, t);
      expect(await isDup(wallet3000, t.add(const Duration(seconds: 20))), isFalse);
      insertSms(wallet3000, t.add(const Duration(seconds: 20)));
      expect(await isDup(wallet1000, t.add(const Duration(minutes: 1))), isFalse);
      insertSms(wallet1000, t.add(const Duration(minutes: 1)));
      expect(await isDup(wallet0, t.add(const Duration(minutes: 1, seconds: 30))), isFalse);
    });

    test('identical body re-delivered from another sender is a duplicate', () async {
      final t = DateTime(2026, 7, 14, 22, 58);
      insertSms(wallet4000, t, sender: 'JM-PHONPE-S');
      expect(
        await isDup(wallet4000, t.add(const Duration(minutes: 1)), sender: 'VA-PHONPE-S'),
        isTrue,
      );
    });

    test('re-delivery with different whitespace is still a duplicate', () async {
      final t = DateTime(2026, 7, 14, 22, 58);
      insertSms(wallet4000, t);
      expect(
        await isDup(wallet4000.replaceAll('Rs. 4000', 'Rs.  4000'), t.add(const Duration(minutes: 2))),
        isTrue,
      );
    });

    test('same balance reported twice is a duplicate even with different wording', () async {
      final t = DateTime(2026, 7, 14, 22, 58);
      insertSms(wallet4000, t);
      // Same payment, same balance, slightly different template.
      expect(
        await isDup(
          "You've paid Rs.1000 via PhonePe wallet. Remaining balance: Rs. 4000. Not you? Call us on 022-68727374.",
          t.add(const Duration(minutes: 3)),
        ),
        isTrue,
      );
    });
  });

  group('PhonePe gift card (embedded second-precision timestamp)', () {
    test('distinct payments with different embedded times are not duplicates', () async {
      final t = DateTime(2026, 2, 22, 18, 11);
      insertSms(
        "You've paid Rs.40 via PhonePe gift card to Ojas canteen on Feb 22, 2026 at 6:11:43 PM. Not you? Call us on 022-68727374.",
        t,
      );
      expect(
        await isDup(
          "You've paid Rs.40 via PhonePe gift card to Ojas canteen on Feb 22, 2026 at 6:18:02 PM. Not you? Call us on 022-68727374.",
          t.add(const Duration(minutes: 7)),
        ),
        isFalse,
      );
    });

    test('same embedded time from differently-spaced re-delivery is a duplicate', () async {
      final t = DateTime(2026, 2, 22, 18, 11);
      insertSms(
        "You've paid Rs.40 via PhonePe gift card to Ojas canteen on Feb 22, 2026 at 6:11:43 PM. Not you? Call us on 022-68727374.",
        t,
      );
      expect(
        await isDup(
          "You've paid  Rs.40 via PhonePe gift card to Ojas canteen on Feb 22, 2026 at 6:11:43 PM.  Not you? Call us on 022-68727374.",
          t.add(const Duration(minutes: 5)),
        ),
        isTrue,
      );
    });
  });

  group('cross-format duplicates (same event, different wording)', () {
    test('IT refund reported by two SBI systems is deduplicated', () async {
      final t1 = DateTime(2026, 7, 11, 8, 34);
      insertSms(
        'Your A/C XXXX020587 has credit for ITDTAX REFUND 2026-27 LREPS480 of Rs 11,640.00 on 11/07/26. Avl Bal Rs 79,593.25.-SBI',
        t1,
        sender: 'JD-CBSSBI-S',
      );
      expect(
        await isDup(
          'Dear Customer, For PAN XXXXXX808L, An IT Refund amount of Rs 11640 for AY-2026-27 has been credited to your account XXXXXXX0587 on 2026-07-11. -SBI',
          DateTime(2026, 7, 11, 8, 55),
          sender: 'VK-SBIBNK-S',
        ),
        isTrue,
      );
    });

    test('same-amount credit on a different day is not a duplicate', () async {
      insertSms(
        'Your A/C XXXX020587 has credit for ITDTAX REFUND 2026-27 LREPS480 of Rs 11,640.00 on 11/07/26. Avl Bal Rs 79,593.25.-SBI',
        DateTime(2026, 7, 11, 8, 34),
      );
      expect(
        await isDup(
          'Dear Customer, For PAN XXXXXX808L, An IT Refund amount of Rs 11640 for AY-2025-26 has been credited to your account XXXXXXX0587 on 2026-07-12. -SBI',
          DateTime(2026, 7, 12, 9, 0),
        ),
        isFalse,
      );
    });
  });

  group('notification + SMS pairing', () {
    const sbiSms =
        'Dear UPI user A/C X0587 debited by 500.00 on date 13Apr26 trf to Rohit Rajput Refno 203884917693 If not u? call-1800111109 for other services-18001234-SBI';

    test('bank SMS with ref deduplicates against earlier ref-less notification', () async {
      final t = DateTime(2026, 4, 13, 0, 52);
      // GPay-style notification: no ref, has counterparty.
      final notifParsed = UpiParser.parseNotification(
        packageName: 'com.google.android.apps.nbu.paisa.user',
        title: 'Payment sent',
        text: 'You paid ₹500 to Rohit Rajput',
      );
      fakeDb.records.add(TransactionRecord(
        id: 'n1',
        amount: notifParsed.amount!,
        type: notifParsed.type!,
        counterpartyName: notifParsed.counterpartyName,
        source: 'notification',
        rawText: 'Payment sent You paid ₹500 to Rohit Rajput',
        dedupHash: dedupService.generateDedupHash(
            notifParsed, 'Payment sent You paid ₹500 to Rohit Rajput'),
        transactionDate: t,
        createdAt: t,
        updatedAt: t,
      ));

      expect(await isDup(sbiSms, t.add(const Duration(minutes: 2))), isTrue);
    });

    test('duplicates straddling a 10-minute boundary are caught (sliding window)', () async {
      // Old bucketed hash treated :09 and :11 as different windows.
      final t = DateTime(2026, 4, 13, 10, 9);
      final notifParsed = UpiParser.parseNotification(
        packageName: 'com.phonepe.app',
        title: 'Payment successful',
        text: 'You paid ₹250 to Swiggy',
      );
      fakeDb.records.add(TransactionRecord(
        id: 'n2',
        amount: notifParsed.amount!,
        type: notifParsed.type!,
        counterpartyName: notifParsed.counterpartyName,
        source: 'notification',
        rawText: 'Payment successful You paid ₹250 to Swiggy',
        dedupHash: dedupService.generateDedupHash(
            notifParsed, 'Payment successful You paid ₹250 to Swiggy'),
        transactionDate: t,
        createdAt: t,
        updatedAt: t,
      ));

      expect(
        await isDup(
          'Rs 250 debited from A/c XX1234 paid to Swiggy via UPI',
          DateTime(2026, 4, 13, 10, 11),
        ),
        isTrue,
      );
    });

    test('distinct payments with different refs are never deduplicated', () async {
      final t = DateTime(2026, 4, 7, 12, 0);
      insertSms(
        'Dear UPI user A/C X0587 debited by 25.00 on date 07Apr26 trf to KANCHAN WO GOVIN Refno 203489899690 If not u? call-1800111109-SBI',
        t,
      );
      // Same amount, same person, three minutes later — but a different Refno.
      expect(
        await isDup(
          'Dear UPI user A/C X0587 debited by 25.00 on date 07Apr26 trf to KANCHAN WO GOVIN Refno 203847248179 If not u? call-1800111109-SBI',
          t.add(const Duration(minutes: 3)),
        ),
        isFalse,
      );
    });
  });

  group('manual entries', () {
    test('incoming SMS deduplicates against a matching manual entry', () async {
      final t = DateTime(2026, 4, 13, 10, 0);
      fakeDb.records.add(TransactionRecord(
        id: 'm1',
        amount: 250,
        type: TransactionType.debit,
        counterpartyName: 'Swiggy',
        source: 'manual',
        dedupHash: 'manual:some-uuid',
        transactionDate: t,
        createdAt: t,
        updatedAt: t,
      ));
      expect(
        await isDup('Rs 250 debited from A/c XX1234 paid to Swiggy via UPI',
            t.add(const Duration(minutes: 5))),
        isTrue,
      );
    });

    test('different counterparty is not deduplicated against a manual entry', () async {
      final t = DateTime(2026, 4, 13, 10, 0);
      fakeDb.records.add(TransactionRecord(
        id: 'm2',
        amount: 250,
        type: TransactionType.debit,
        counterpartyName: 'Zomato',
        source: 'manual',
        dedupHash: 'manual:other-uuid',
        transactionDate: t,
        createdAt: t,
        updatedAt: t,
      ));
      expect(
        await isDup('Rs 250 debited from A/c XX1234 paid to Swiggy via UPI',
            t.add(const Duration(minutes: 5))),
        isFalse,
      );
    });
  });
}
