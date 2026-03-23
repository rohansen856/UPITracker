import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:receipt/models/transaction_record.dart';

/// Tests the core query/filter/summary logic used by TransactionProvider,
/// exercised against a real in-memory SQLite DB to verify SQL correctness.
/// The actual provider depends on native channels (SMS, notifications, widget),
/// so we test the database query logic directly.

Future<Database> _createDb() async {
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
  return db;
}

TransactionRecord _rec({
  required String id,
  double amount = 100,
  TransactionType type = TransactionType.debit,
  String? upiApp = 'gpay',
  String? counterpartyName,
  required DateTime transactionDate,
}) {
  return TransactionRecord(
    id: id, amount: amount, type: type, upiApp: upiApp,
    counterpartyName: counterpartyName,
    source: 'sms', dedupHash: 'h_$id',
    transactionDate: transactionDate,
    createdAt: transactionDate, updatedAt: transactionDate,
  );
}

Future<List<TransactionRecord>> queryWithEffectiveFrom({
  required Database db,
  DateTime? filterFrom,
  DateTime? startDate,
  String? typeFilter,
  String? appFilter,
}) async {
  DateTime? effectiveFrom;
  if (filterFrom != null && startDate != null) {
    effectiveFrom = filterFrom.isAfter(startDate) ? filterFrom : startDate;
  } else {
    effectiveFrom = filterFrom ?? startDate;
  }

  final where = <String>[];
  final args = <dynamic>[];
  if (typeFilter != null) { where.add('transaction_type = ?'); args.add(typeFilter); }
  if (appFilter != null) { where.add('upi_app = ?'); args.add(appFilter); }
  if (effectiveFrom != null) { where.add('transaction_date >= ?'); args.add(effectiveFrom.toIso8601String()); }

  final result = await db.query(
    'transactions',
    where: where.isEmpty ? null : where.join(' AND '),
    whereArgs: args.isEmpty ? null : args,
    orderBy: 'transaction_date DESC',
  );
  return result.map((m) => TransactionRecord.fromMap(m)).toList();
}

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await _createDb();
    await db.insert('transactions', _rec(id: 'old1', transactionDate: DateTime(2026, 3, 15), amount: 500).toMap());
    await db.insert('transactions', _rec(id: 'old2', transactionDate: DateTime(2026, 4, 1), amount: 200, type: TransactionType.credit).toMap());
    await db.insert('transactions', _rec(id: 'new1', transactionDate: DateTime(2026, 4, 10), amount: 100).toMap());
    await db.insert('transactions', _rec(id: 'new2', transactionDate: DateTime(2026, 4, 12), amount: 300, upiApp: 'phonepe').toMap());
    await db.insert('transactions', _rec(id: 'new3', transactionDate: DateTime(2026, 4, 13), amount: 50, type: TransactionType.credit).toMap());
  });

  tearDown(() async {
    await db.close();
  });

  group('_effectiveFromDate logic', () {
    test('no startDate, no filterFrom → returns all 5', () async {
      final txns = await queryWithEffectiveFrom(db: db);
      expect(txns.length, 5);
    });

    test('startDate=Apr10, no filterFrom → excludes old records', () async {
      final txns = await queryWithEffectiveFrom(db: db, startDate: DateTime(2026, 4, 10));
      expect(txns.length, 3);
      expect(txns.every((t) => !t.transactionDate.isBefore(DateTime(2026, 4, 10))), isTrue);
    });

    test('no startDate, filterFrom=Apr12 → only Apr12+', () async {
      final txns = await queryWithEffectiveFrom(db: db, filterFrom: DateTime(2026, 4, 12));
      expect(txns.length, 2);
    });

    test('startDate=Apr10, filterFrom=Apr1 → startDate wins (Apr10)', () async {
      final txns = await queryWithEffectiveFrom(db: db, startDate: DateTime(2026, 4, 10), filterFrom: DateTime(2026, 4, 1));
      expect(txns.length, 3);
    });

    test('startDate=Apr10, filterFrom=Apr12 → filterFrom wins (Apr12)', () async {
      final txns = await queryWithEffectiveFrom(db: db, startDate: DateTime(2026, 4, 10), filterFrom: DateTime(2026, 4, 12));
      expect(txns.length, 2);
    });
  });

  group('Filter combinations', () {
    test('typeFilter=debit with startDate', () async {
      final txns = await queryWithEffectiveFrom(db: db, startDate: DateTime(2026, 4, 10), typeFilter: 'debit');
      expect(txns.length, 2);
      expect(txns.every((t) => t.type == TransactionType.debit), isTrue);
    });

    test('appFilter=phonepe', () async {
      final txns = await queryWithEffectiveFrom(db: db, appFilter: 'phonepe');
      expect(txns.length, 1);
      expect(txns.first.id, 'new2');
    });

    test('combined typeFilter + appFilter + startDate', () async {
      final txns = await queryWithEffectiveFrom(
        db: db, typeFilter: 'debit', appFilter: 'gpay', startDate: DateTime(2026, 4, 10),
      );
      expect(txns.length, 1);
      expect(txns.first.id, 'new1');
    });
  });

  group('Summary with analytics date clamping', () {
    test('30 day period without start date includes old data', () async {
      final now = DateTime(2026, 4, 13);
      final from = now.subtract(const Duration(days: 30));
      final where = 'transaction_date >= ? AND transaction_date <= ? AND transaction_type = ?';
      final debit = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE $where',
        [from.toIso8601String(), now.toIso8601String(), 'debit'],
      );
      expect((debit.first['total'] as num).toDouble(), 900.0);
    });

    test('30 day period clamped to start date Apr10 excludes old data', () async {
      final now = DateTime(2026, 4, 13);
      var from = now.subtract(const Duration(days: 30));
      final startDate = DateTime(2026, 4, 10);
      if (from.isBefore(startDate)) from = startDate;

      final where = 'transaction_date >= ? AND transaction_date <= ? AND transaction_type = ?';
      final debit = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE $where',
        [from.toIso8601String(), now.toIso8601String(), 'debit'],
      );
      expect((debit.first['total'] as num).toDouble(), 400.0);

      final credit = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE $where',
        [from.toIso8601String(), now.toIso8601String(), 'credit'],
      );
      expect((credit.first['total'] as num).toDouble(), 50.0);
    });

    test('week period naturally excludes old data', () async {
      final now = DateTime(2026, 4, 13);
      final from = now.subtract(const Duration(days: 7));
      final where = 'transaction_date >= ? AND transaction_date <= ? AND transaction_type = ?';
      final debit = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE $where',
        [from.toIso8601String(), now.toIso8601String(), 'debit'],
      );
      expect((debit.first['total'] as num).toDouble(), 400.0);
    });

    test('today summary only captures today', () async {
      final todayStart = DateTime(2026, 4, 13);
      final todayEnd = DateTime(2026, 4, 13, 23, 59, 59);
      final where = 'transaction_date >= ? AND transaction_date <= ? AND transaction_type = ?';

      final debit = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE $where',
        [todayStart.toIso8601String(), todayEnd.toIso8601String(), 'debit'],
      );
      expect((debit.first['total'] as num).toDouble(), 0.0);

      final credit = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM transactions WHERE $where',
        [todayStart.toIso8601String(), todayEnd.toIso8601String(), 'credit'],
      );
      expect((credit.first['total'] as num).toDouble(), 50.0);
    });
  });

  group('Daily totals for chart', () {
    test('groups correctly by date and type', () async {
      final result = await db.rawQuery('''
        SELECT DATE(transaction_date) as date, transaction_type, SUM(amount) as total
        FROM transactions
        WHERE transaction_date >= ? AND transaction_date <= ?
        GROUP BY DATE(transaction_date), transaction_type ORDER BY date ASC
      ''', [DateTime(2026, 4, 10).toIso8601String(), DateTime(2026, 4, 13, 23, 59).toIso8601String()]);

      expect(result.length, greaterThanOrEqualTo(3));

      final apr12Debit = result.firstWhere(
        (r) => r['date'] == '2026-04-12' && r['transaction_type'] == 'debit',
      );
      expect((apr12Debit['total'] as num).toDouble(), 300.0);
    });
  });
}
