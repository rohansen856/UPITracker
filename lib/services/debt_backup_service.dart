import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/debt_entry.dart';

/// Raised when the backup cannot be written, or exists but cannot be read.
class DebtBackupException implements Exception {
  DebtBackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Handles export/import of debt entries to a JSON file
/// (`UPITracker/debts_ledger.json`).
///
/// On Android the file lives in the app-specific external directory
/// (`Android/data/<package>/files`), which needs no storage permission and is
/// not readable by other apps. It is removed when the app is uninstalled.
class DebtBackupService {
  static const _folderName = 'UPITracker';
  static const _fileName = 'debts_ledger.json';

  static Future<File> _backupFile() async {
    final base = await _baseDirectory();
    final dir = Directory('${base.path}/$_folderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$_fileName');
  }

  static Future<Directory> _baseDirectory() async {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  /// Writes all debts to the backup file and returns its path.
  static Future<String> export(List<DebtEntry> debts) async {
    try {
      final file = await _backupFile();
      final content = const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'debts': debts.map((d) => d.toMap()).toList(),
      });
      await file.writeAsString(content, flush: true);
      return file.path;
    } on FileSystemException catch (e) {
      throw DebtBackupException('Could not write backup: ${e.message}');
    }
  }

  /// Parsed entries from the backup file, or null if there is no backup.
  /// Throws [DebtBackupException] if a backup exists but is unreadable, so
  /// a corrupt file is not mistaken for "no backup".
  static Future<List<DebtEntry>?> readBackup() async {
    final file = await _backupFile();
    if (!await file.exists()) return null;
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final list = (map['debts'] as List).cast<Map<String, dynamic>>();
      return list.map(DebtEntry.fromMap).toList();
    } catch (e) {
      throw DebtBackupException('Backup file is unreadable: $e');
    }
  }

  /// Returns true if a backup file exists on disk.
  static Future<bool> backupExists() async {
    final file = await _backupFile();
    return file.exists();
  }
}
