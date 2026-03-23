// ignore_for_file: avoid_print
import 'dart:io';
import 'package:postgres/postgres.dart';

/// Standalone script to seed the remote PostgreSQL (Neon) database.
/// Run: dart run scripts/seed_db.dart
Future<void> main() async {
  final dbUrl = Platform.environment['DATABASE_URL'] ??
      _readDotEnv('.env')['DATABASE_URL'];

  if (dbUrl == null || dbUrl.isEmpty) {
    print('ERROR: DATABASE_URL not set. Set it in .env or as an environment variable.');
    exit(1);
  }

  print('Connecting to database...');

  final uri = Uri.parse(dbUrl.replaceFirst('postgresql://', 'http://'));
  final userParts = uri.userInfo.split(':');

  final conn = await Connection.open(
    Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'neondb',
      username: userParts.first,
      password: userParts.length > 1 ? userParts.sublist(1).join(':') : '',
    ),
    settings: ConnectionSettings(sslMode: SslMode.require),
  );

  print('Connected. Creating tables...');

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
  await conn.execute(
    'CREATE INDEX IF NOT EXISTS idx_remote_type ON transactions(transaction_type)',
  );
  await conn.execute(
    'CREATE INDEX IF NOT EXISTS idx_remote_app ON transactions(upi_app)',
  );

  print('Tables and indexes created successfully.');

  final result = await conn.execute('SELECT COUNT(*) FROM transactions');
  final count = result.first[0] as int;
  print('Current record count: $count');

  await conn.close();
  print('Done. Database is ready.');
}

Map<String, String> _readDotEnv(String path) {
  final file = File(path);
  if (!file.existsSync()) return {};

  final map = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx < 0) continue;
    final key = trimmed.substring(0, idx).trim();
    var value = trimmed.substring(idx + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    map[key] = value;
  }
  return map;
}
