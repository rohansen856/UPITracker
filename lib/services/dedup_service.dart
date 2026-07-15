import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../database/local_database.dart';
import '../models/transaction_record.dart';
import '../services/upi_parser.dart';

/// Idempotency for captured transactions. A single payment can surface
/// several times: app notification + bank SMS, the same SMS re-delivered
/// from different sender IDs (JD-/VA-/JM-PHONPE), or two differently-worded
/// SMS about the same event (e.g. an IT refund reported by two SBI systems).
///
/// Tiered decision:
///  1. UPI txn id / bank reference hash — exact, time-independent.
///  2. Normalized-body hash — catches identical bodies from other sender IDs.
///  3. Fuzzy candidate comparison (same amount + direction, nearby in time)
///     with discriminators so that genuinely distinct back-to-back payments
///     are NOT collapsed:
///       - differing refs            → distinct
///       - differing balance-after   → distinct (consecutive wallet payments)
///       - differing embedded time   → distinct
///       - equal balance / embedded timestamp, or same counterparty within
///         a ±10-minute sliding window → duplicate
class DedupService {
  static const _fuzzyWindow = Duration(minutes: 10);

  final LocalDatabase _localDb;

  DedupService(this._localDb);

  /// The hash stored on the record: ref-based when the message carries a
  /// UPI transaction id / bank reference, else a normalized-body hash.
  String generateDedupHash(ParsedUpi parsed, String rawText) {
    if (parsed.upiTransactionId != null && parsed.upiTransactionId!.isNotEmpty) {
      return _hash('txn:${parsed.upiTransactionId}');
    }
    if (parsed.bankReference != null && parsed.bankReference!.isNotEmpty) {
      return _hash('ref:${parsed.bankReference}');
    }
    return _hash('body:${normalizeBody(rawText)}');
  }

  Future<bool> isDuplicate(ParsedUpi parsed, DateTime timestamp, String dedupHash) async {
    // Tiers 1+2: exact hash match (ref or identical normalized body).
    if (await _localDb.existsByDedupHash(dedupHash)) return true;
    return _fuzzyDuplicate(parsed, timestamp);
  }

  Future<bool> _fuzzyDuplicate(ParsedUpi parsed, DateTime timestamp) async {
    final amount = parsed.amount;
    final type = parsed.type;
    if (amount == null || type == null) return false;

    // Wide enough for the same-day cross-format rule; the ±10 min sliding
    // window is applied per candidate below.
    final dayStart = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final candidates = await _localDb.findDedupCandidates(
      amount: amount,
      type: type.value,
      from: dayStart.subtract(_fuzzyWindow),
      to: dayStart.add(const Duration(days: 1)).add(_fuzzyWindow),
    );

    for (final candidate in candidates) {
      if (_isSameEvent(parsed, timestamp, candidate)) return true;
    }
    return false;
  }

  bool _isSameEvent(ParsedUpi parsed, DateTime timestamp, TransactionRecord candidate) {
    // Differing explicit references → definitely distinct payments.
    final incomingRef = parsed.upiTransactionId ?? parsed.bankReference;
    final candidateRef = candidate.upiTransactionId ?? candidate.bankReference;
    if (incomingRef != null && candidateRef != null && incomingRef != candidateRef) {
      return false;
    }

    // Re-parse the candidate's message for balance / embedded timestamp
    // (they are not stored columns). Manual entries have no raw text.
    ParsedUpi? candidateParsed;
    if (candidate.rawText != null && candidate.rawText!.isNotEmpty) {
      candidateParsed = UpiParser.parseSms(sender: '', body: candidate.rawText!);
    }

    // Balance-after is a strong discriminator: the same event re-reported
    // carries the same balance; consecutive identical payments do not.
    final b1 = parsed.balanceAfter;
    final b2 = candidateParsed?.balanceAfter;
    if (b1 != null && b2 != null) return b1 == b2;

    // Second-precision embedded timestamps identify the event exactly.
    final e1 = parsed.embeddedDate;
    final e2 = candidateParsed?.embeddedDate;
    if (e1 != null && e2 != null &&
        parsed.embeddedDateHasTime && (candidateParsed?.embeddedDateHasTime ?? false)) {
      return e1 == e2;
    }

    final compatibleParty = _compatibleCounterparty(parsed, candidate);

    // Date-only embedded dates: same amount + direction + day + compatible
    // counterparty → the same event reported in two formats.
    if (e1 != null && e2 != null) {
      final sameDay = e1.year == e2.year && e1.month == e2.month && e1.day == e2.day;
      return sameDay && compatibleParty;
    }

    // Fallback: sliding ±10 min window around the candidate's own time
    // (notification + SMS pair, or re-delivery without any discriminator).
    final delta = timestamp.difference(candidate.transactionDate).abs();
    return delta <= _fuzzyWindow && compatibleParty;
  }

  bool _compatibleCounterparty(ParsedUpi parsed, TransactionRecord candidate) {
    final a = (parsed.counterpartyName ?? parsed.counterpartyUpiId ?? '').toLowerCase().trim();
    final b = (candidate.counterpartyName ?? candidate.counterpartyUpiId ?? '').toLowerCase().trim();
    return a.isEmpty || b.isEmpty || a == b;
  }

  /// Lowercased, whitespace-collapsed message body — identical across the
  /// sender-ID variants (JD-/VA-/JM-…) the same SMS gets delivered from.
  static String normalizeBody(String rawText) {
    return rawText.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _hash(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }
}
