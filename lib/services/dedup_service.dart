import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../database/local_database.dart';
import '../services/upi_parser.dart';

class DedupService {
  final LocalDatabase _localDb;

  DedupService(this._localDb);

  /// Generates a dedup hash based on amount, approximate time, and counterparty.
  /// Transactions within a 10-minute window with same amount and counterparty
  /// are considered duplicates.
  String generateDedupHash(ParsedUpi parsed, DateTime timestamp) {
    if (parsed.upiTransactionId != null && parsed.upiTransactionId!.isNotEmpty) {
      return _hash('txn:${parsed.upiTransactionId}');
    }

    if (parsed.bankReference != null && parsed.bankReference!.isNotEmpty) {
      return _hash('ref:${parsed.bankReference}');
    }

    final roundedTime = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
      timestamp.hour,
      (timestamp.minute ~/ 10) * 10,
    );
    final amountStr = parsed.amount?.toStringAsFixed(2) ?? '0';
    final counterparty = (parsed.counterpartyName ?? parsed.counterpartyUpiId ?? '')
        .toLowerCase()
        .trim();

    return _hash('amt:$amountStr|time:${roundedTime.toIso8601String()}|party:$counterparty');
  }

  Future<bool> isDuplicate(String dedupHash) async {
    return _localDb.existsByDedupHash(dedupHash);
  }

  String _hash(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }
}
