import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:receipt/models/transaction_record.dart';
import 'package:receipt/services/upi_parser.dart';
import 'package:receipt/services/dedup_service.dart';
import 'package:receipt/database/local_database.dart';
import 'package:mockito/mockito.dart';
import 'package:uuid/uuid.dart';

class FakeLocalDatabase extends Fake implements LocalDatabase {
  final Database db;
  FakeLocalDatabase(this.db);

  @override
  Future<bool> existsByDedupHash(String dedupHash) async {
    final result = await db.query('transactions', where: 'dedup_hash = ?', whereArgs: [dedupHash], limit: 1);
    return result.isNotEmpty;
  }

  @override
  Future<List<TransactionRecord>> findDedupCandidates({
    required double amount,
    required String type,
    required DateTime from,
    required DateTime to,
  }) async {
    // Same SQL as the real DAO.
    final result = await db.query(
      'transactions',
      where: 'amount = ? AND transaction_type = ? AND transaction_date >= ? AND transaction_date <= ?',
      whereArgs: [amount, type, from.toIso8601String(), to.toIso8601String()],
    );
    return result.map((m) => TransactionRecord.fromMap(m)).toList();
  }

  @override
  Future<int> insertTransaction(TransactionRecord record) {
    return db.insert('transactions', record.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<List<TransactionRecord>> getAllTransactions({
    String? typeFilter,
    String? appFilter,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchQuery,
    int? limit,
    int? offset,
  }) async {
    final where = <String>[];
    final args = <dynamic>[];
    if (typeFilter != null) { where.add('transaction_type = ?'); args.add(typeFilter); }
    if (appFilter != null) { where.add('upi_app = ?'); args.add(appFilter); }
    if (fromDate != null) { where.add('transaction_date >= ?'); args.add(fromDate.toIso8601String()); }
    if (toDate != null) { where.add('transaction_date <= ?'); args.add(toDate.toIso8601String()); }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      where.add('(counterparty_name LIKE ? OR note LIKE ? OR tags LIKE ? OR description LIKE ?)');
      final q = '%$searchQuery%';
      args.addAll([q, q, q, q]);
    }
    final result = await db.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'transaction_date DESC',
      limit: limit,
      offset: offset,
    );
    return result.map((m) => TransactionRecord.fromMap(m)).toList();
  }

  @override
  Future<Map<String, double>> getSummary({DateTime? fromDate, DateTime? toDate}) async {
    final where = <String>[];
    final args = <dynamic>[];
    if (fromDate != null) { where.add('transaction_date >= ?'); args.add(fromDate.toIso8601String()); }
    if (toDate != null) { where.add('transaction_date <= ?'); args.add(toDate.toIso8601String()); }
    where.add('transaction_type = ?');
    final debitArgs = [...args, 'debit'];
    final creditArgs = [...args, 'credit'];
    final whereClause = 'WHERE ${where.join(' AND ')}';
    final debitResult = await db.rawQuery('SELECT COALESCE(SUM(amount), 0) as total FROM transactions $whereClause', debitArgs);
    final creditResult = await db.rawQuery('SELECT COALESCE(SUM(amount), 0) as total FROM transactions $whereClause', creditArgs);
    final totalDebit = (debitResult.first['total'] as num?)?.toDouble() ?? 0.0;
    final totalCredit = (creditResult.first['total'] as num?)?.toDouble() ?? 0.0;
    return {'total_spent': totalDebit, 'total_received': totalCredit, 'net': totalCredit - totalDebit};
  }
}

Future<Database> _createInMemoryDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      amount REAL NOT NULL,
      transaction_type TEXT NOT NULL,
      upi_app TEXT,
      upi_transaction_id TEXT,
      bank_reference TEXT,
      counterparty_name TEXT,
      counterparty_upi_id TEXT,
      account_info TEXT,
      description TEXT,
      note TEXT,
      tags TEXT DEFAULT '',
      latitude REAL,
      longitude REAL,
      location_name TEXT,
      source TEXT NOT NULL,
      raw_text TEXT,
      dedup_hash TEXT NOT NULL,
      transaction_date TEXT NOT NULL,
      synced INTEGER DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('CREATE INDEX idx_dedup ON transactions(dedup_hash)');
  return db;
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late FakeLocalDatabase fakeDb;
  late DedupService dedupService;
  const uuid = Uuid();

  setUp(() async {
    db = await _createInMemoryDb();
    fakeDb = FakeLocalDatabase(db);
    dedupService = DedupService(fakeDb);
  });

  tearDown(() async {
    await db.close();
  });

  Future<bool> processMessage({
    required String sender,
    required String body,
    required DateTime timestamp,
    DateTime? startDate,
  }) async {
    if (!UpiParser.isUpiRelated(body)) return false;

    final parsed = UpiParser.parseSms(sender: sender, body: body);
    if (!parsed.isValid) return false;

    if (startDate != null && timestamp.isBefore(startDate)) return false;

    final dedupHash = dedupService.generateDedupHash(parsed, body);
    if (await dedupService.isDuplicate(parsed, timestamp, dedupHash)) return false;

    final record = TransactionRecord(
      id: uuid.v4(),
      amount: parsed.amount!,
      type: parsed.type!,
      upiApp: parsed.upiApp,
      upiTransactionId: parsed.upiTransactionId,
      bankReference: parsed.bankReference,
      counterpartyName: parsed.counterpartyName,
      counterpartyUpiId: parsed.counterpartyUpiId,
      accountInfo: parsed.accountInfo,
      description: parsed.description,
      source: 'sms',
      rawText: body,
      dedupHash: dedupHash,
      transactionDate: timestamp,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await fakeDb.insertTransaction(record);
    return true;
  }

  group('Full pipeline: parse → dedup → insert → query', () {
    test('processes real SBI debit SMS end-to-end', () async {
      final inserted = await processMessage(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 50.00 on date 11Apr26 trf to M S SURINDER KUM Refno 602560907627 If not u? call-1800111109 for other services-18001234-SBI',
        timestamp: DateTime(2026, 4, 11, 14, 30),
      );

      expect(inserted, isTrue);
      final all = await fakeDb.getAllTransactions();
      expect(all.length, 1);
      expect(all.first.amount, 50.00);
      expect(all.first.type, TransactionType.debit);
      expect(all.first.counterpartyName, 'M S SURINDER KUM');
      expect(all.first.bankReference, '602560907627');
    });

    test('processes real SBI credit SMS end-to-end', () async {
      final inserted = await processMessage(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.280.00 on 13-04-26 transfer from PANDEYNITINNAGENDRA Ref No 175732878237 -SBI',
        timestamp: DateTime(2026, 4, 13, 9, 0),
      );

      expect(inserted, isTrue);
      final all = await fakeDb.getAllTransactions();
      expect(all.length, 1);
      expect(all.first.amount, 280.00);
      expect(all.first.type, TransactionType.credit);
    });

    test('deduplicates same SMS received from JD and VA senders', () async {
      const body = 'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969 If not u? call-1800111109';
      final ts = DateTime(2026, 4, 12, 10, 0);

      final first = await processMessage(sender: 'JD-SBIUPI-S', body: body, timestamp: ts);
      final second = await processMessage(sender: 'VA-SBIUPI-S', body: body, timestamp: ts);

      expect(first, isTrue);
      expect(second, isFalse);
      final all = await fakeDb.getAllTransactions();
      expect(all.length, 1);
    });

    test('rejects non-UPI messages', () async {
      final inserted = await processMessage(
        sender: 'JD-SBIBNK',
        body: 'Your OTP for transaction is 856432. Do not share with anyone.',
        timestamp: DateTime(2026, 4, 13),
      );
      expect(inserted, isFalse);
    });

    test('rejects invalid parsed messages (no amount)', () async {
      final inserted = await processMessage(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user, your transaction has failed. Try again.',
        timestamp: DateTime(2026, 4, 13),
      );
      expect(inserted, isFalse);
    });
  });

  group('Start date filtering', () {
    test('rejects transactions before start date', () async {
      final inserted = await processMessage(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 100.00 on date 05Apr26 trf to SOMEONE Refno 123456789012',
        timestamp: DateTime(2026, 4, 5),
        startDate: DateTime(2026, 4, 10),
      );
      expect(inserted, isFalse);
      final all = await fakeDb.getAllTransactions();
      expect(all.length, 0);
    });

    test('accepts transactions on or after start date', () async {
      final inserted = await processMessage(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 100.00 on date 10Apr26 trf to SOMEONE Refno 123456789012',
        timestamp: DateTime(2026, 4, 10),
        startDate: DateTime(2026, 4, 10),
      );
      expect(inserted, isTrue);
    });
  });

  group('Summary respects date range', () {
    test('summary excludes data outside range', () async {
      await processMessage(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 200.00 on date 08Apr26 trf to OLD VENDOR Refno 111111111111',
        timestamp: DateTime(2026, 4, 8),
      );
      await processMessage(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 100.00 on date 11Apr26 trf to NEW VENDOR Refno 222222222222',
        timestamp: DateTime(2026, 4, 11),
      );
      await processMessage(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.50.00 on 12-04-26 transfer from FRIEND Ref No 333333333333 -SBI',
        timestamp: DateTime(2026, 4, 12),
      );

      final allSummary = await fakeDb.getSummary();
      expect(allSummary['total_spent'], 300.0);
      expect(allSummary['total_received'], 50.0);

      final filteredSummary = await fakeDb.getSummary(fromDate: DateTime(2026, 4, 10));
      expect(filteredSummary['total_spent'], 100.0);
      expect(filteredSummary['total_received'], 50.0);
      expect(filteredSummary['net'], -50.0);
    });
  });

  group('PhonePe wallet / gift card end-to-end', () {
    test('four consecutive identical wallet payments are all kept', () async {
      // Real failure case: same amount, no ref, no counterparty — only the
      // remaining balance distinguishes them. Old bucketed dedup kept one.
      final bodies = [
        "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 4000. To top-up click https://phone.pe/PHONPE/ws",
        "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 3000. To top-up click https://phone.pe/PHONPE/ws",
        "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 1000. To top-up click https://phone.pe/PHONPE/ws",
        "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 0. To top-up click https://phone.pe/PHONPE/ws",
      ];
      var t = DateTime(2026, 7, 14, 22, 57);
      for (final body in bodies) {
        expect(await processMessage(sender: 'JM-PHONPE-S', body: body, timestamp: t), isTrue);
        t = t.add(const Duration(seconds: 40));
      }
      final all = await fakeDb.getAllTransactions();
      expect(all.length, 4);
      expect(await fakeDb.getSummary(), containsPair('total_spent', 4000.0));
    });

    test('re-delivery of the same wallet payment from another sender is dropped', () async {
      const body =
          "You've paid Rs. 180 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 2007.5. To top-up click https://phone.pe/PHONPE/ws";
      final t = DateTime(2026, 7, 10, 13, 5);
      expect(await processMessage(sender: 'JD-PHONPE-S', body: body, timestamp: t), isTrue);
      expect(
        await processMessage(
            sender: 'VA-PHONPE-S', body: body, timestamp: t.add(const Duration(minutes: 1))),
        isFalse,
      );
      expect((await fakeDb.getAllTransactions()).length, 1);
    });

    test('gift card payment parses with counterparty and is inserted', () async {
      final inserted = await processMessage(
        sender: 'JM-PHONPE-S',
        body:
            "You've paid Rs.207 via PhonePe gift card to SWIGGY on May 29, 2026 at 9:38:00 PM. Not you? Call us on 022-68727374. Remaining balance Rs.1534.",
        timestamp: DateTime(2026, 5, 29, 21, 38),
      );
      expect(inserted, isTrue);
      final all = await fakeDb.getAllTransactions();
      expect(all.first.amount, 207);
      expect(all.first.type, TransactionType.debit);
      expect(all.first.counterpartyName, 'SWIGGY');
    });
  });

  group('Cross-format refund dedup end-to-end', () {
    test('IT refund reported in two formats is inserted once', () async {
      final first = await processMessage(
        sender: 'JD-CBSSBI-S',
        body:
            'Your A/C XXXX020587 has credit for ITDTAX REFUND 2026-27 LREPS480 of Rs 11,640.00 on 11/07/26. Avl Bal Rs 79,593.25.-SBI',
        timestamp: DateTime(2026, 7, 11, 8, 34),
      );
      final second = await processMessage(
        sender: 'VK-SBIBNK-S',
        body:
            'Dear Customer, For PAN XXXXXX808L, An IT Refund amount of Rs 11640 for AY-2026-27 has been credited to your account XXXXXXX0587 on 2026-07-11. -SBI',
        timestamp: DateTime(2026, 7, 11, 8, 55),
      );
      expect(first, isTrue);
      expect(second, isFalse);
      final all = await fakeDb.getAllTransactions();
      expect(all.length, 1);
      expect(all.first.type, TransactionType.credit);
      expect(all.first.amount, 11640.0);
    });
  });

  group('Multiple transactions and ordering', () {
    test('processes batch of real messages in chronological order', () async {
      final messages = [
        ('JD-SBIUPI-S', 'Dear UPI user A/C X0587 debited by 50.00 on date 11Apr26 trf to VENDOR A Refno 111111111111', DateTime(2026, 4, 11, 8, 0)),
        ('VA-SBIUPI-S', 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.20.00 on 11-04-26 transfer from FRIEND Ref No 222222222222 -SBI', DateTime(2026, 4, 11, 10, 0)),
        ('JD-SBIUPI-S', 'Dear UPI user A/C X0587 debited by 40.00 on date 12Apr26 trf to VENDOR B Refno 333333333333', DateTime(2026, 4, 12, 9, 0)),
        ('VA-SBIUPI-S', 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.280.00 on 13-04-26 transfer from PERSON Ref No 444444444444 -SBI', DateTime(2026, 4, 13, 14, 0)),
      ];

      for (final (sender, body, ts) in messages) {
        await processMessage(sender: sender, body: body, timestamp: ts);
      }

      final all = await fakeDb.getAllTransactions();
      expect(all.length, 4);
      expect(all.first.transactionDate.isAfter(all.last.transactionDate), isTrue);

      final summary = await fakeDb.getSummary();
      expect(summary['total_spent'], 90.0);
      expect(summary['total_received'], 300.0);
      expect(summary['net'], 210.0);
    });
  });
}
