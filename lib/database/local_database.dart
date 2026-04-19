import 'package:sqflite/sqflite.dart';
import '../models/debt_entry.dart';
import '../models/transaction_record.dart';

class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._internal();
  factory LocalDatabase() => _instance;
  LocalDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = '$dbPath/upi_tracker.db';

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createTransactionsTable(db);
    await _createDebtsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createDebtsTable(db);
    }
  }

  Future<void> _createTransactionsTable(Database db) async {
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
  }

  Future<void> _createDebtsTable(Database db) async {
    await db.execute('''
      CREATE TABLE debts (
        id TEXT PRIMARY KEY,
        direction TEXT NOT NULL,
        counterparty TEXT NOT NULL,
        amount REAL NOT NULL,
        reason TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        due_date TEXT,
        settled INTEGER DEFAULT 0,
        settled_at TEXT,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_debts_counterparty ON debts(counterparty)');
    await db.execute('CREATE INDEX idx_debts_direction ON debts(direction)');
    await db.execute('CREATE INDEX idx_debts_settled ON debts(settled)');
  }

  Future<int> insertTransaction(TransactionRecord record) async {
    final db = await database;
    return db.insert(
      'transactions',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<bool> existsByDedupHash(String dedupHash) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'dedup_hash = ?',
      whereArgs: [dedupHash],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<TransactionRecord>> getAllTransactions({
    String? typeFilter,
    String? appFilter,
    DateTime? fromDate,
    DateTime? toDate,
    String? searchQuery,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];

    if (typeFilter != null) {
      where.add('transaction_type = ?');
      args.add(typeFilter);
    }
    if (appFilter != null) {
      where.add('upi_app = ?');
      args.add(appFilter);
    }
    if (fromDate != null) {
      where.add('transaction_date >= ?');
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      where.add('transaction_date <= ?');
      args.add(toDate.toIso8601String());
    }
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

  Future<TransactionRecord?> getTransactionById(String id) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return TransactionRecord.fromMap(result.first);
  }

  Future<int> updateTransaction(TransactionRecord record) async {
    final db = await database;
    return db.update(
      'transactions',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<int> deleteTransaction(String id) async {
    final db = await database;
    return db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TransactionRecord>> getUnsyncedTransactions() async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'synced = 0',
      orderBy: 'created_at ASC',
    );
    return result.map((m) => TransactionRecord.fromMap(m)).toList();
  }

  Future<void> markSynced(List<String> ids) async {
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.update(
        'transactions',
        {'synced': 1, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, double>> getSummary({DateTime? fromDate, DateTime? toDate}) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];

    if (fromDate != null) {
      where.add('transaction_date >= ?');
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      where.add('transaction_date <= ?');
      args.add(toDate.toIso8601String());
    }

    where.add('transaction_type = ?');

    final debitArgs = [...args, 'debit'];
    final creditArgs = [...args, 'credit'];
    final whereClause = 'WHERE ${where.join(' AND ')}';

    final debitResult = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM transactions $whereClause',
      debitArgs,
    );
    final creditResult = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM transactions $whereClause',
      creditArgs,
    );

    final totalDebit = (debitResult.first['total'] as num?)?.toDouble() ?? 0.0;
    final totalCredit = (creditResult.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'total_spent': totalDebit,
      'total_received': totalCredit,
      'net': totalCredit - totalDebit,
    };
  }

  Future<Map<String, double>> getSpendingByApp({DateTime? fromDate, DateTime? toDate}) async {
    final db = await database;
    final where = <String>['transaction_type = ?'];
    final args = <dynamic>['debit'];

    if (fromDate != null) {
      where.add('transaction_date >= ?');
      args.add(fromDate.toIso8601String());
    }
    if (toDate != null) {
      where.add('transaction_date <= ?');
      args.add(toDate.toIso8601String());
    }

    final result = await db.rawQuery(
      'SELECT upi_app, SUM(amount) as total FROM transactions WHERE ${where.join(' AND ')} GROUP BY upi_app ORDER BY total DESC',
      args,
    );

    return {for (var row in result) (row['upi_app'] as String? ?? 'unknown'): (row['total'] as num).toDouble()};
  }

  Future<List<Map<String, dynamic>>> getDailyTotals({
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        DATE(transaction_date) as date,
        transaction_type,
        SUM(amount) as total
      FROM transactions
      WHERE transaction_date >= ? AND transaction_date <= ?
      GROUP BY DATE(transaction_date), transaction_type
      ORDER BY date ASC
    ''', [fromDate.toIso8601String(), toDate.toIso8601String()]);

    return result;
  }

  Future<int> getTransactionCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM transactions');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<String?> getFirstTransactionId() async {
    final db = await database;
    final result = await db.query('transactions', columns: ['id'], orderBy: 'transaction_date ASC', limit: 1);
    return result.isEmpty ? null : result.first['id'] as String?;
  }

  Future<String?> getLastTransactionId() async {
    final db = await database;
    final result = await db.query('transactions', columns: ['id'], orderBy: 'transaction_date DESC', limit: 1);
    return result.isEmpty ? null : result.first['id'] as String?;
  }

  Future<void> markAllUnsynced() async {
    final db = await database;
    await db.update('transactions', {'synced': 0, 'updated_at': DateTime.now().toIso8601String()});
  }

  // ───────────────────────── Debts table DAO ─────────────────────────

  Future<int> insertDebt(DebtEntry entry) async {
    final db = await database;
    return db.insert('debts', entry.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateDebt(DebtEntry entry) async {
    final db = await database;
    return db.update('debts', entry.toMap(), where: 'id = ?', whereArgs: [entry.id]);
  }

  Future<int> deleteDebt(String id) async {
    final db = await database;
    return db.delete('debts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<DebtEntry>> getAllDebts({bool? settledOnly}) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];
    if (settledOnly != null) {
      where.add('settled = ?');
      args.add(settledOnly ? 1 : 0);
    }
    final result = await db.query(
      'debts',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'settled ASC, created_at DESC',
    );
    return result.map((m) => DebtEntry.fromMap(m)).toList();
  }

  Future<DebtEntry?> getDebtById(String id) async {
    final db = await database;
    final rows = await db.query('debts', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return DebtEntry.fromMap(rows.first);
  }
}
