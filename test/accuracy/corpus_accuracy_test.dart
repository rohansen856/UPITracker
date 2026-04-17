import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/transaction_record.dart';
import 'package:receipt/services/ml/classifiers.dart';
import 'package:receipt/services/ml/message_pipeline.dart';
import 'package:receipt/services/upi_parser.dart';

/// Corpus-wide accuracy sweep: every **real** UPI SMS in `data/upi*.csv`
/// must survive the stacked pipeline end-to-end.
///
/// This is the strictest safety net we have against training regressions.
/// If a future model update causes even one legitimate transaction to be
/// dropped, this test will explode and point at the offender.
///
/// CI-friendly: if the CSVs are absent (they are gitignored — see
/// `data/README.md`) the test short-circuits with `markTestSkipped` rather
/// than failing.
void main() {
  final root = Directory.current.path;
  final dataDir = Directory('$root/data');

  setUpAll(() {
    void loadInto(dynamic cls, String path) {
      final f = File('$root/$path');
      if (f.existsSync()) {
        cls.engine.loadFromJsonStringForTest(f.readAsStringSync());
      }
    }

    loadInto(SpamFilter.instance, 'assets/spam_model.json');
    loadInto(TransactionalClassifier.instance, 'assets/transactional_model.json');
    loadInto(DirectionClassifier.instance, 'assets/direction_model.json');
  });

  /// Parses a UPI CSV the same way `scripts/ml_core.py::load_upi_corpus`
  /// does — split on the rightmost comma, strip quotes. Returns
  /// `(text, expectedDirection)` pairs.
  List<({String text, TransactionType direction})> readUpiCsv(File f) {
    final out = <({String text, TransactionType direction})>[];
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      if (i == 0 && line.toLowerCase().startsWith('msg')) continue;
      final idx = line.lastIndexOf(',');
      if (idx < 0) continue;
      var text = line.substring(0, idx).trim();
      final label = line.substring(idx + 1).trim().toLowerCase();
      if (text.startsWith('"') && text.endsWith('"')) {
        text = text.substring(1, text.length - 1);
      }
      if (text.isEmpty || (label != 'ham' && label != 'spam')) continue;
      final low = text.toLowerCase();
      final TransactionType? dir = low.contains('credited')
          ? TransactionType.credit
          : (low.contains('debited') ? TransactionType.debit : null);
      if (dir == null) continue;
      out.add((text: text, direction: dir));
    }
    return out;
  }

  test('every real UPI SMS in data/upi*.csv is ingested with the right direction', () {
    if (!dataDir.existsSync()) {
      markTestSkipped('data/ missing — skipping corpus sweep. '
          'See data/README.md for how to fetch the dataset bundle.');
      return;
    }

    final csvs = dataDir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'upi\d+\.csv$').hasMatch(f.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    if (csvs.isEmpty) {
      markTestSkipped('No data/upi*.csv files found — skipping corpus sweep.');
      return;
    }

    if (!SpamFilter.instance.isLoaded ||
        !TransactionalClassifier.instance.isLoaded ||
        !DirectionClassifier.instance.isLoaded) {
      markTestSkipped(
        'ML models not found under assets/. Run '
        '`python3 scripts/train_all_models.py` first.',
      );
      return;
    }

    final failures = <String>[];
    var total = 0;
    var ingested = 0;
    var directionRight = 0;

    for (final csv in csvs) {
      final rows = readUpiCsv(csv);
      for (final row in rows) {
        total++;

        if (!UpiParser.isUpiRelated(row.text)) {
          failures.add('[keyword] ${csv.uri.pathSegments.last}: "${_trunc(row.text)}"');
          continue;
        }
        final decision = MessagePipeline.instance.evaluate(row.text);
        if (!decision.shouldIngest) {
          failures.add('[${decision.stage}] ${csv.uri.pathSegments.last}: '
              '"${_trunc(row.text)}" — $decision');
          continue;
        }
        final parsed = UpiParser.parseSms(sender: 'SBIINB', body: row.text);
        if (!parsed.isValid) {
          failures.add('[parser] ${csv.uri.pathSegments.last}: "${_trunc(row.text)}"');
          continue;
        }
        ingested++;

        // If the direction model has made a confident call, it should match
        // the keyword in the text. Abstentions (null) are fine.
        final hint = decision.directionHint;
        final expected = row.direction == TransactionType.credit
            ? TxDirection.credit
            : TxDirection.debit;
        if (hint != null && hint != expected) {
          failures.add(
            '[direction] ${csv.uri.pathSegments.last}: '
            '"${_trunc(row.text)}" — parser=${row.direction}, '
            'model=${hint}, p_credit=${decision.creditProbability}',
          );
        } else if (hint == expected) {
          directionRight++;
        }
      }
    }

    // Print a concise coverage summary so flaky failures are easy to read.
    // ignore: avoid_print
    print(
      'corpus sweep: $total SMS across ${csvs.length} files — '
      'ingested=$ingested (${(100 * ingested / total).toStringAsFixed(1)}%), '
      'direction-confident=$directionRight, failures=${failures.length}',
    );

    expect(
      failures,
      isEmpty,
      reason: 'Corpus-wide accuracy regression:\n  ${failures.join('\n  ')}',
    );
    // These hard guarantees fail loudly on training drift:
    expect(ingested, total, reason: 'every real UPI SMS must pass the gate');
    expect(
      directionRight / total,
      greaterThan(0.90),
      reason: 'direction model must be confident on >90% of real UPI SMS',
    );
  });
}

String _trunc(String s, [int n = 90]) =>
    s.length > n ? '${s.substring(0, n)}…' : s;
