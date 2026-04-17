import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/services/ml/classifiers.dart';

/// Cross-model consistency / sanity audit.
///
/// Every real UPI SMS should score:
///   * LOW on the spam classifier        (≪ default threshold)
///   * HIGH on the transactional gate    (≫ default threshold)
///
/// Similarly, every curated non-transactional sample should score:
///   * LOW on the transactional classifier
///
/// This catches silent model drift that the corpus-ingest test might miss
/// if we ever lowered thresholds to hide regressions.
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
  });

  List<String> readUpiTexts(File f) {
    final out = <String>[];
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
      if (text.isNotEmpty && (label == 'ham' || label == 'spam')) {
        out.add(text);
      }
    }
    return out;
  }

  test('real UPI SMS score low on spam and high on transactional', () {
    if (!dataDir.existsSync()) {
      markTestSkipped('data/ missing — skipping consistency audit.');
      return;
    }

    if (!SpamFilter.instance.isLoaded || !TransactionalClassifier.instance.isLoaded) {
      markTestSkipped('ML models not found — run trainer first.');
      return;
    }

    final csvs = dataDir
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'upi\d+\.csv$').hasMatch(f.path))
        .toList();
    if (csvs.isEmpty) {
      markTestSkipped('No data/upi*.csv files found — skipping.');
      return;
    }

    final spamThr = SpamFilter.instance.defaultThreshold;
    final txThr = TransactionalClassifier.instance.defaultThreshold;

    var n = 0;
    var spamViolations = 0;
    var txViolations = 0;
    var spamMaxP = 0.0;
    var txMinP = 1.0;
    final offenders = <String>[];

    for (final csv in csvs) {
      for (final text in readUpiTexts(csv)) {
        n++;
        final ps = SpamFilter.instance.spamProbability(text);
        final pt = TransactionalClassifier.instance.transactionalProbability(text);
        if (ps > spamMaxP) spamMaxP = ps;
        if (pt < txMinP) txMinP = pt;
        if (ps >= spamThr) {
          spamViolations++;
          offenders.add(
            '[spam p=${ps.toStringAsFixed(3)} ≥ $spamThr] '
            '${csv.uri.pathSegments.last}: ${_trunc(text)}',
          );
        }
        if (pt < txThr) {
          txViolations++;
          offenders.add(
            '[tx p=${pt.toStringAsFixed(3)} < $txThr] '
            '${csv.uri.pathSegments.last}: ${_trunc(text)}',
          );
        }
      }
    }

    // ignore: avoid_print
    print(
      'consistency audit on $n real UPI SMS: '
      'max P(spam)=${spamMaxP.toStringAsFixed(3)}, '
      'min P(tx)=${txMinP.toStringAsFixed(3)}, '
      'spam violations=$spamViolations, tx violations=$txViolations',
    );

    expect(spamViolations, 0,
        reason: 'real UPI SMS must never score as spam:\n  '
            '${offenders.take(10).join('\n  ')}');
    expect(txViolations, 0,
        reason: 'real UPI SMS must always pass the transactional gate:\n  '
            '${offenders.take(10).join('\n  ')}');
  });

  test('curated non-transactional samples are consistently rejected', () {
    if (!TransactionalClassifier.instance.isLoaded) {
      markTestSkipped('transactional_model.json missing');
      return;
    }

    // Hand-picked OTPs / alerts / bills / declines / chat — all must score
    // below the transactional threshold. This is what enables layer 2 to
    // protect the ledger from bogus entries.
    const nonTx = [
      'Dear Customer, 478912 is your OTP for transaction of Rs 500 on HDFC card ending 1234. Do not share. Valid for 5 min.',
      '123456 is your OTP. Do not share with anyone. -SBI',
      '765432 is OTP to add beneficiary in your a/c XX1234. Valid for 5 mins. -AXIS',
      'Your A/c XX0587 balance is Rs 3,245.67 as on 12-04-26 17:00. -SBI',
      'Mini-statement A/c XX1234: 10Apr Rs500 DR, 09Apr Rs1000 CR, 08Apr Rs200 DR. Bal Rs 10,000. -HDFC',
      'Your monthly statement for A/c XX1234 is ready. Download at hdfcbank.com/estmt',
      'Dear Cust, your HDFC CC ending 1234 bill of Rs 5,678 is due on 15-04-26. Pay now to avoid late fee.',
      'Reminder: your SBI Credit Card payment of Rs 2,500 is due tomorrow.',
      'Your electricity bill of Rs 1,250 is due on 20-Apr-26. Pay via BBPS.',
      'Dear Customer, your UPI payment of Rs 500 to merchant@upi on 10-04-26 FAILED. Amount will be reversed. -SBI',
      'Your transaction of Rs 250 on card XX1234 was DECLINED on 10-04-26. -HDFC',
      'Your KYC is complete. Thank you for banking with us. -SBI',
      'Cheque no 123456 of Rs 10,000 has been cleared in A/c XX1234. -HDFC',
    ];

    final txThr = TransactionalClassifier.instance.defaultThreshold;
    final violations = <String>[];
    var maxP = 0.0;

    for (final body in nonTx) {
      final p = TransactionalClassifier.instance.transactionalProbability(body);
      if (p > maxP) maxP = p;
      if (p >= txThr) violations.add('[p=${p.toStringAsFixed(3)}] ${_trunc(body)}');
    }

    // ignore: avoid_print
    print('non-tx audit on ${nonTx.length} samples: '
        'max P(tx)=${maxP.toStringAsFixed(3)} (threshold $txThr)');

    expect(violations, isEmpty,
        reason: 'non-transactional samples slipped through layer 2:\n  '
            '${violations.join('\n  ')}');
  });
}

String _trunc(String s, [int n = 90]) =>
    s.length > n ? '${s.substring(0, n)}…' : s;
