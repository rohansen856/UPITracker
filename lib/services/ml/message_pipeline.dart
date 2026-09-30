import 'package:flutter/foundation.dart';

import '../../models/transaction_record.dart';
import 'classifiers.dart';

/// Outcome of the stacked classifier pipeline for a single inbound message.
///
/// The pipeline always returns one of these; callers use [shouldIngest] to
/// decide whether to hand the text off to the regex parser and ultimately
/// the database. [directionHint] is an independent signal that can be used
/// to cross-check the parser's keyword-based detection.
@immutable
class PipelineDecision {
  const PipelineDecision({
    required this.shouldIngest,
    required this.stage,
    required this.reason,
    required this.spamProbability,
    required this.transactionalProbability,
    this.directionHint,
    this.creditProbability,
  });

  /// Whether the message should be passed to the parser + DB.
  final bool shouldIngest;

  /// Which stage produced the decision (spam/transactional/passed).
  final String stage;

  /// Human-readable reason suitable for debug logs.
  final String reason;

  final double spamProbability;
  final double transactionalProbability;
  final TxDirection? directionHint;
  final double? creditProbability;

  /// Convenience: does the direction model disagree with [parsed]?
  bool disagreesWithParser(TransactionType? parsed) {
    if (directionHint == null || parsed == null) return false;
    if (parsed == TransactionType.debit && directionHint == TxDirection.credit) return true;
    if (parsed == TransactionType.credit && directionHint == TxDirection.debit) return true;
    return false;
  }

  @override
  String toString() =>
      'PipelineDecision(stage=$stage, ingest=$shouldIngest, '
      'spam=${spamProbability.toStringAsFixed(3)}, '
      'tx=${transactionalProbability.toStringAsFixed(3)}, '
      'dir=$directionHint${creditProbability == null ? '' : ' (p=${creditProbability!.toStringAsFixed(3)})'})';
}

/// Orchestrates the stacked classifier cascade used to gate inbound SMS and
/// notifications before they reach [UpiParser] and the local database.
///
/// Layers, in order:
///   1. [SpamFilter]              — drops promotional / scam messages.
///   2. [TransactionalClassifier] — drops OTPs, balance alerts, reminders.
///   3. [DirectionClassifier]     — cross-checks the parser's debit/credit.
///
/// All three models are loaded once on [load] and live in RAM for the
/// remainder of the process. Inference is ~microseconds per message.
class MessagePipeline {
  MessagePipeline._();
  static final MessagePipeline instance = MessagePipeline._();

  /// Loads all three models in parallel. Idempotent; safe to call from any
  /// number of providers / services. Model-load failures are swallowed —
  /// the pipeline degrades gracefully (fail-open for dropped messages).
  Future<void> load() async {
    await Future.wait([
      SpamFilter.instance.load(),
      TransactionalClassifier.instance.load(),
      DirectionClassifier.instance.load(),
    ]);
  }

  bool get isLoaded =>
      SpamFilter.instance.isLoaded &&
      TransactionalClassifier.instance.isLoaded &&
      DirectionClassifier.instance.isLoaded;

  // A 12-digit NPCI RRN/UTR next to a settlement verb is hard evidence that
  // money actually moved. Real-inbox sweeps showed the classifiers dropping
  // whole bank templates of this shape (e.g. "Your A/c *X is credited with
  // Rs.Y ... RRN Z" at p_tx≈0.42), so the models may not veto them.
  static final RegExp _settlementRefRe = RegExp(
    r'(?:\bRRN|\bUTR|\bRef\s*No\.?|\bRefno|\bUPI\s*Ref(?:\s*No)?|\bUPI)[\s:.\-]*\d{12}\b',
    caseSensitive: false,
  );
  static final RegExp _settlementVerbRe = RegExp(
    r'\b(?:credited|debited|debit|credit|sent|received|paid)\b',
    caseSensitive: false,
  );

  // DLT-registered SMS headers ("JD-SBIUPI-S", "VM-INDBNK"). Raw phone
  // numbers are excluded so an SMS from an arbitrary sender cannot bypass the
  // models just by quoting an RRN.
  static final RegExp _registeredHeaderRe = RegExp(r'^[A-Z]{2}-[A-Za-z0-9]{3,9}(?:-[STG])?$');

  /// Whether [text] carries hard settlement evidence. [sender] is the SMS
  /// sender id; pass null for notifications, which are already limited to an
  /// allowlist of payment-app packages on the native side.
  @visibleForTesting
  static bool hasSettlementEvidence(String text, {String? sender}) {
    if (sender != null && !_registeredHeaderRe.hasMatch(sender)) return false;
    return _settlementRefRe.hasMatch(text) && _settlementVerbRe.hasMatch(text);
  }

  /// Runs the full cascade and returns a structured decision.
  PipelineDecision evaluate(String text, {String? sender}) {
    final spam = SpamFilter.instance;
    final tx = TransactionalClassifier.instance;
    final dir = DirectionClassifier.instance;
    final settled = hasSettlementEvidence(text, sender: sender);

    final pSpam = spam.isLoaded ? spam.spamProbability(text) : 0.0;
    if (!settled && spam.isLoaded && pSpam >= spam.defaultThreshold) {
      return PipelineDecision(
        shouldIngest: false,
        stage: 'spam',
        reason: 'spam p=${pSpam.toStringAsFixed(3)}',
        spamProbability: pSpam,
        transactionalProbability: 0.0,
      );
    }

    final pTx = tx.isLoaded ? tx.transactionalProbability(text) : 1.0;
    if (!settled && tx.isLoaded && pTx < tx.defaultThreshold) {
      return PipelineDecision(
        shouldIngest: false,
        stage: 'transactional',
        reason: 'not-transactional p=${pTx.toStringAsFixed(3)}',
        spamProbability: pSpam,
        transactionalProbability: pTx,
      );
    }

    double? pCredit;
    TxDirection? direction;
    if (dir.isLoaded) {
      pCredit = dir.creditProbability(text);
      // Only emit a direction hint when the model is reasonably confident,
      // so that the parser-disagreement warning in TransactionProvider only
      // fires on meaningful mismatches.
      direction = dir.predict(text, confidence: 0.65);
    }

    return PipelineDecision(
      shouldIngest: true,
      stage: 'passed',
      reason: settled ? 'settlement-evidence' : 'ok',
      spamProbability: pSpam,
      transactionalProbability: pTx,
      directionHint: direction,
      creditProbability: pCredit,
    );
  }
}
