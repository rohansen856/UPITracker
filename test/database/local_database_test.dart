import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:receipt/models/transaction_record.dart';

/// Thin wrapper around a real SQLite database that mirrors LocalDatabase's
/// schema and methods, so we can test SQL logic without the singleton / path deps.
class TestableLocalDatabase {
  final Database db;
  TestableLocalDatabase(this.db);

  static Future<TestableLocalDatabase> create() async {
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
    await db.execute('CREATE INDEX idx_date ON transactions(transaction_date)');
    await db.execute('CREATE INDEX idx_synced ON transactions(synced)');
    await db.execute('CREATE INDEX idx_type ON transactions(transaction_type)');
    return TestableLocalDatabase(db);
  }

  Future<int> insertTransaction(TransactionRecord record) {
    return db.insert('transactions', record.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> existsByDedupHash(String dedupHash) async {
    final result = await db.query('transactions', where: 'dedup_hash = ?', whereArgs: [dedupHash], limit: 1);
    return result.isNotEmpty;
  }

  Future<List<TransactionRecord>> getAllTransactions({
    String? typeFilter, String? appFilter, DateTime? fromDate, DateTime? toDate, String? searchQuery, int? limit, int? offset,
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
      limit: limit, offset: offset,
    );
    return result.map((m) => TransactionRecord.fromMap(m)).toList();
  }

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

  Future<Map<String, double>> getSpendingByApp({DateTime? fromDate, DateTime? toDate}) async {
    final where = <String>['transaction_type = ?'];
    final args = <dynamic>['debit'];
    if (fromDate != null) { where.add('transaction_date >= ?'); args.add(fromDate.toIso8601String()); }
    if (toDate != null) { where.add('transaction_date <= ?'); args.add(toDate.toIso8601String()); }
    final result = await db.rawQuery(
      'SELECT upi_app, SUM(amount) as total FROM transactions WHERE ${where.join(' AND ')} GROUP BY upi_app ORDER BY total DESC', args,
    );
    return {for (var row in result) (row['upi_app'] as String? ?? 'unknown'): (row['total'] as num).toDouble()};
  }

  Future<List<Map<String, dynamic>>> getDailyTotals({required DateTime fromDate, required DateTime toDate}) async {
    return db.rawQuery('''
      SELECT DATE(transaction_date) as date, transaction_type, SUM(amount) as total
      FROM transactions WHERE transaction_date >= ? AND transaction_date <= ?
      GROUP BY DATE(transaction_date), transaction_type ORDER BY date ASC
    ''', [fromDate.toIso8601String(), toDate.toIso8601String()]);
  }

  Future<int> getTransactionCount() async {
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM transactions');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> markSynced(List<String> ids) async {
    final batch = db.batch();
    for (final id in ids) {
      batch.update('transactions', {'synced': 1, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<void> markAllUnsynced() async {
    await db.update('transactions', {'synced': 0, 'updated_at': DateTime.now().toIso8601String()});
  }

  Future<String?> getFirstTransactionId() async {
    final result = await db.query('transactions', columns: ['id'], orderBy: 'transaction_date ASC', limit: 1);
    return result.isEmpty ? null : result.first['id'] as String?;
  }

  Future<String?> getLastTransactionId() async {
    final result = await db.query('transactions', columns: ['id'], orderBy: 'transaction_date DESC', limit: 1);
    return result.isEmpty ? null : result.first['id'] as String?;
  }

  Future<int> deleteTransaction(String id) => db.delete('transactions', where: 'id = ?', whereArgs: [id]);

  Future<int> updateTransaction(TransactionRecord record) => db.update('transactions', record.toMap(), where: 'id = ?', whereArgs: [record.id]);

  Future<void> close() => db.close();
}

TransactionRecord _makeRecord({
  String id = 'id-1',
  double amount = 100,
  TransactionType type = TransactionType.debit,
  String? upiApp = 'gpay',
  String? counterpartyName = 'Test User',
  String source = 'sms',
  String dedupHash = 'hash1',
  DateTime? transactionDate,
  bool synced = false,
  String? note,
  String tags = '',
}) {
  final now = transactionDate ?? DateTime(2026, 4, 13, 10, 0);
  return TransactionRecord(
    id: id, amount: amount, type: type, upiApp: upiApp,
    counterpartyName: counterpartyName, source: source,
    dedupHash: dedupHash, transactionDate: now, synced: synced,
    note: note, tags: tags,
    createdAt: now, updatedAt: now,
  );
}

void main() {
  sqfliteFfiInit();

  late TestableLocalDatabase localDb;

  setUp(() async {
    localDb = await TestableLocalDatabase.create();
  });

  tearDown(() async {
    await localDb.close();
  });

  group('insertTransaction', () {
    test('inserts a record and retrieves it', () async {
      final record = _makeRecord();
      await localDb.insertTransaction(record);
      final all = await localDb.getAllTransactions();
      expect(all.length, 1);
      expect(all.first.id, 'id-1');
      expect(all.first.amount, 100);
    });

    test('ignores duplicate primary key', () async {
      final r1 = _makeRecord();
      final r2 = _makeRecord(amount: 999, dedupHash: 'hash2');
      await localDb.insertTransaction(r1);
      await localDb.insertTransaction(r2);
      final all = await localDb.getAllTransactions();
      expect(all.length, 1);
      expect(all.first.amount, 100);
    });
  });

  group('existsByDedupHash', () {
    test('returns false for non-existent hash', () async {
      expect(await localDb.existsByDedupHash('nope'), isFalse);
    });

    test('returns true after inserting matching record', () async {
      await localDb.insertTransaction(_makeRecord(dedupHash: 'uniq'));
      expect(await localDb.existsByDedupHash('uniq'), isTrue);
    });
  });

  group('getAllTransactions - filters', () {
    setUp(() async {
      await localDb.insertTransaction(_makeRecord(id: 'd1', type: TransactionType.debit, upiApp: 'gpay', amount: 200, dedupHash: 'h1', transactionDate: DateTime(2026, 4, 10)));
      await localDb.insertTransaction(_makeRecord(id: 'c1', type: TransactionType.credit, upiApp: 'phonepe', amount: 300, dedupHash: 'h2', transactionDate: DateTime(2026, 4, 11)));
      await localDb.insertTransaction(_makeRecord(id: 'd2', type: TransactionType.debit, upiApp: 'paytm', amount: 150, dedupHash: 'h3', transactionDate: DateTime(2026, 4, 12), note: 'lunch bill', counterpartyName: 'Swiggy'));
      await localDb.insertTransaction(_makeRecord(id: 'c2', type: TransactionType.credit, upiApp: 'gpay', amount: 500, dedupHash: 'h4', transactionDate: DateTime(2026, 4, 13)));
    });

    test('returns all ordered by date descending', () async {
      final all = await localDb.getAllTransactions();
      expect(all.length, 4);
      expect(all.first.id, 'c2');
      expect(all.last.id, 'd1');
    });

    test('filters by type', () async {
      final debits = await localDb.getAllTransactions(typeFilter: 'debit');
      expect(debits.length, 2);
      expect(debits.every((t) => t.type == TransactionType.debit), isTrue);
    });

    test('filters by app', () async {
      final gpay = await localDb.getAllTransactions(appFilter: 'gpay');
      expect(gpay.length, 2);
    });

    test('filters by date range', () async {
      final range = await localDb.getAllTransactions(
        fromDate: DateTime(2026, 4, 11),
        toDate: DateTime(2026, 4, 12, 23, 59),
      );
      expect(range.length, 2);
    });

    test('filters by search query in counterparty', () async {
      final results = await localDb.getAllTransactions(searchQuery: 'Swiggy');
      expect(results.length, 1);
      expect(results.first.id, 'd2');
    });

    test('filters by search query in note', () async {
      final results = await localDb.getAllTransactions(searchQuery: 'lunch');
      expect(results.length, 1);
    });

    test('combined filters work', () async {
      final results = await localDb.getAllTransactions(typeFilter: 'debit', appFilter: 'gpay');
      expect(results.length, 1);
      expect(results.first.id, 'd1');
    });

    test('limit and offset work', () async {
      final page1 = await localDb.getAllTransactions(limit: 2);
      expect(page1.length, 2);
      final page2 = await localDb.getAllTransactions(limit: 2, offset: 2);
      expect(page2.length, 2);
      expect(page1.first.id, isNot(page2.first.id));
    });
  });

  group('getSummary', () {
    setUp(() async {
      await localDb.insertTransaction(_makeRecord(id: 'd1', type: TransactionType.debit, amount: 200, dedupHash: 'h1', transactionDate: DateTime(2026, 4, 10)));
      await localDb.insertTransaction(_makeRecord(id: 'd2', type: TransactionType.debit, amount: 300, dedupHash: 'h2', transactionDate: DateTime(2026, 4, 12)));
      await localDb.insertTransaction(_makeRecord(id: 'c1', type: TransactionType.credit, amount: 150, dedupHash: 'h3', transactionDate: DateTime(2026, 4, 11)));
    });

    test('returns correct totals for all data', () async {
      final summary = await localDb.getSummary();
      expect(summary['total_spent'], 500.0);
      expect(summary['total_received'], 150.0);
      expect(summary['net'], -350.0);
    });

    test('respects fromDate filter', () async {
      final summary = await localDb.getSummary(fromDate: DateTime(2026, 4, 11));
      expect(summary['total_spent'], 300.0);
      expect(summary['total_received'], 150.0);
    });

    test('respects toDate filter', () async {
      final summary = await localDb.getSummary(toDate: DateTime(2026, 4, 10, 23, 59));
      expect(summary['total_spent'], 200.0);
      expect(summary['total_received'], 0.0);
    });

    test('returns zeros when no data matches', () async {
      final summary = await localDb.getSummary(fromDate: DateTime(2026, 5, 1));
      expect(summary['total_spent'], 0.0);
      expect(summary['total_received'], 0.0);
      expect(summary['net'], 0.0);
    });
  });

  group('getSpendingByApp', () {
    setUp(() async {
      await localDb.insertTransaction(_makeRecord(id: '1', type: TransactionType.debit, upiApp: 'gpay', amount: 200, dedupHash: 'h1'));
      await localDb.insertTransaction(_makeRecord(id: '2', type: TransactionType.debit, upiApp: 'gpay', amount: 100, dedupHash: 'h2'));
      await localDb.insertTransaction(_makeRecord(id: '3', type: TransactionType.debit, upiApp: 'paytm', amount: 500, dedupHash: 'h3'));
      await localDb.insertTransaction(_makeRecord(id: '4', type: TransactionType.credit, upiApp: 'gpay', amount: 1000, dedupHash: 'h4'));
    });

    test('groups debits by app, ignores credits', () async {
      final byApp = await localDb.getSpendingByApp();
      expect(byApp['paytm'], 500.0);
      expect(byApp['gpay'], 300.0);
      expect(byApp.containsKey('credit'), isFalse);
    });
  });

  group('getDailyTotals', () {
    test('groups by date and type', () async {
      await localDb.insertTransaction(_makeRecord(id: '1', type: TransactionType.debit, amount: 100, dedupHash: 'h1', transactionDate: DateTime(2026, 4, 10, 8, 0)));
      await localDb.insertTransaction(_makeRecord(id: '2', type: TransactionType.debit, amount: 200, dedupHash: 'h2', transactionDate: DateTime(2026, 4, 10, 14, 0)));
      await localDb.insertTransaction(_makeRecord(id: '3', type: TransactionType.credit, amount: 50, dedupHash: 'h3', transactionDate: DateTime(2026, 4, 10, 10, 0)));
      await localDb.insertTransaction(_makeRecord(id: '4', type: TransactionType.debit, amount: 75, dedupHash: 'h4', transactionDate: DateTime(2026, 4, 11, 10, 0)));

      final totals = await localDb.getDailyTotals(
        fromDate: DateTime(2026, 4, 10),
        toDate: DateTime(2026, 4, 11, 23, 59),
      );

      final april10Debit = totals.firstWhere((r) => r['date'] == '2026-04-10' && r['transaction_type'] == 'debit');
      expect((april10Debit['total'] as num).toDouble(), 300.0);

      final april10Credit = totals.firstWhere((r) => r['date'] == '2026-04-10' && r['transaction_type'] == 'credit');
      expect((april10Credit['total'] as num).toDouble(), 50.0);
    });
  });

  group('sync operations', () {
    test('markSynced updates records', () async {
      await localDb.insertTransaction(_makeRecord(id: 'a', dedupHash: 'h1'));
      await localDb.insertTransaction(_makeRecord(id: 'b', dedupHash: 'h2'));

      await localDb.markSynced(['a']);
      final all = await localDb.getAllTransactions();
      final a = all.firstWhere((t) => t.id == 'a');
      final b = all.firstWhere((t) => t.id == 'b');
      expect(a.synced, isTrue);
      expect(b.synced, isFalse);
    });

    test('markAllUnsynced resets all records', () async {
      await localDb.insertTransaction(_makeRecord(id: 'a', dedupHash: 'h1', synced: true));
      await localDb.insertTransaction(_makeRecord(id: 'b', dedupHash: 'h2', synced: true));
      await localDb.markAllUnsynced();

      final all = await localDb.getAllTransactions();
      expect(all.every((t) => !t.synced), isTrue);
    });
  });

  group('getFirstTransactionId / getLastTransactionId', () {
    test('returns null on empty DB', () async {
      expect(await localDb.getFirstTransactionId(), isNull);
      expect(await localDb.getLastTransactionId(), isNull);
    });

    test('returns correct IDs', () async {
      await localDb.insertTransaction(_makeRecord(id: 'early', dedupHash: 'h1', transactionDate: DateTime(2026, 4, 10)));
      await localDb.insertTransaction(_makeRecord(id: 'middle', dedupHash: 'h2', transactionDate: DateTime(2026, 4, 12)));
      await localDb.insertTransaction(_makeRecord(id: 'late', dedupHash: 'h3', transactionDate: DateTime(2026, 4, 14)));

      expect(await localDb.getFirstTransactionId(), 'early');
      expect(await localDb.getLastTransactionId(), 'late');
    });
  });

  group('deleteTransaction', () {
    test('removes the record', () async {
      await localDb.insertTransaction(_makeRecord(id: 'del', dedupHash: 'hd'));
      expect(await localDb.getTransactionCount(), 1);
      await localDb.deleteTransaction('del');
      expect(await localDb.getTransactionCount(), 0);
    });
  });

  group('updateTransaction', () {
    test('updates note and tags', () async {
      await localDb.insertTransaction(_makeRecord(id: 'upd', dedupHash: 'hu'));
      final original = (await localDb.getAllTransactions()).first;

      final updated = original.copyWith(note: 'New note', tags: 'food');
      await localDb.updateTransaction(updated);

      final reloaded = (await localDb.getAllTransactions()).first;
      expect(reloaded.note, 'New note');
      expect(reloaded.tags, 'food');
    });
  });

  group('getTransactionCount', () {
    test('returns 0 for empty DB', () async {
      expect(await localDb.getTransactionCount(), 0);
    });

    test('returns correct count', () async {
      await localDb.insertTransaction(_makeRecord(id: '1', dedupHash: 'h1'));
      await localDb.insertTransaction(_makeRecord(id: '2', dedupHash: 'h2'));
      await localDb.insertTransaction(_makeRecord(id: '3', dedupHash: 'h3'));
      expect(await localDb.getTransactionCount(), 3);
    });
  });
}
