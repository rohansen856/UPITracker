import 'package:postgres/postgres.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/transaction_record.dart';

class RemoteDatabase {
  static final RemoteDatabase _instance = RemoteDatabase._internal();
  factory RemoteDatabase() => _instance;
  RemoteDatabase._internal();

  Connection? _connection;
  bool _tableCreated = false;

  Future<Connection> _getConnection() async {
    // Neon's pooler closes idle connections. Reusing a closed one fails every
    // later sync with "connection is not open" until the app restarts.
    final existing = _connection;
    if (existing != null && existing.isOpen) return existing;
    _connection = null;

    final dbUrl = dotenv.env['DATABASE_URL'];
    if (dbUrl == null || dbUrl.isEmpty) {
      throw Exception('DATABASE_URL not set in .env');
    }

    final endpoint = Endpoint(
      host: _extractHost(dbUrl),
      port: _extractPort(dbUrl),
      database: _extractDatabase(dbUrl),
      username: _extractUsername(dbUrl),
      password: _extractPassword(dbUrl),
    );

    _connection = await Connection.open(
      endpoint,
      settings: ConnectionSettings(
        sslMode: SslMode.require,
        // Without these a stalled network leaves sync "in progress" forever.
        connectTimeout: const Duration(seconds: 15),
        queryTimeout: const Duration(seconds: 30),
      ),
    );

    if (!_tableCreated) {
      await _ensureTables();
      _tableCreated = true;
    }

    return _connection!;
  }

  String _extractHost(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    return uri.host;
  }

  int _extractPort(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    return uri.hasPort ? uri.port : 5432;
  }

  String _extractDatabase(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'neondb';
  }

  String _extractUsername(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    return Uri.decodeComponent(uri.userInfo.split(':').first);
  }

  String _extractPassword(String url) {
    final uri = Uri.parse(url.replaceFirst('postgresql://', 'http://'));
    final parts = uri.userInfo.split(':');
    // Credentials in a connection URL are percent-encoded (e.g. %40 for @).
    return parts.length > 1 ? Uri.decodeComponent(parts.sublist(1).join(':')) : '';
  }

  Future<void> _ensureTables() async {
    final conn = _connection!;
    await conn.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        amount DOUBLE PRECISION NOT NULL,
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
        latitude DOUBLE PRECISION,
        longitude DOUBLE PRECISION,
        location_name TEXT,
        source TEXT NOT NULL,
        raw_text TEXT,
        dedup_hash TEXT NOT NULL,
        transaction_date TIMESTAMPTZ NOT NULL,
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL
      )
    ''');

    await conn.execute(
      'CREATE INDEX IF NOT EXISTS idx_remote_dedup ON transactions(dedup_hash)',
    );
    await conn.execute(
      'CREATE INDEX IF NOT EXISTS idx_remote_date ON transactions(transaction_date)',
    );
  }

  Future<void> syncTransactions(List<TransactionRecord> records) async {
    if (records.isEmpty) return;
    final conn = await _getConnection();

    for (final record in records) {
      await conn.execute(
        Sql.named('''
          INSERT INTO transactions (
            id, amount, transaction_type, upi_app, upi_transaction_id,
            bank_reference, counterparty_name, counterparty_upi_id,
            account_info, description, note, tags, latitude, longitude,
            location_name, source, raw_text, dedup_hash, transaction_date,
            created_at, updated_at
          ) VALUES (
            @id, @amount, @transaction_type, @upi_app, @upi_transaction_id,
            @bank_reference, @counterparty_name, @counterparty_upi_id,
            @account_info, @description, @note, @tags, @latitude, @longitude,
            @location_name, @source, @raw_text, @dedup_hash, @transaction_date,
            @created_at, @updated_at
          )
          ON CONFLICT (id) DO UPDATE SET
            note = EXCLUDED.note,
            tags = EXCLUDED.tags,
            updated_at = EXCLUDED.updated_at
        '''),
        parameters: {
          'id': record.id,
          'amount': record.amount,
          'transaction_type': record.type.value,
          'upi_app': record.upiApp,
          'upi_transaction_id': record.upiTransactionId,
          'bank_reference': record.bankReference,
          'counterparty_name': record.counterpartyName,
          'counterparty_upi_id': record.counterpartyUpiId,
          'account_info': record.accountInfo,
          'description': record.description,
          'note': record.note,
          'tags': record.tags,
          'latitude': record.latitude,
          'longitude': record.longitude,
          'location_name': record.locationName,
          'source': record.source,
          'raw_text': record.rawText,
          'dedup_hash': record.dedupHash,
          'transaction_date': record.transactionDate,
          'created_at': record.createdAt,
          'updated_at': record.updatedAt,
        },
      );
    }
  }

  Future<int> getRemoteCount() async {
    final conn = await _getConnection();
    final result = await conn.execute('SELECT COUNT(*) FROM transactions');
    return result.first[0] as int;
  }

  Future<bool> existsById(String id) async {
    final conn = await _getConnection();
    final result = await conn.execute(
      Sql.named('SELECT 1 FROM transactions WHERE id = @id LIMIT 1'),
      parameters: {'id': id},
    );
    return result.isNotEmpty;
  }

  Future<void> close() async {
    await _connection?.close();
    _connection = null;
    _tableCreated = false;
  }
}
