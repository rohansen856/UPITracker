import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/services/ml/classifiers.dart';

/// End-to-end test of the SpamFilter against the shipped model JSON.
/// Verifies: (1) numerical parity with Python, (2) correct classification
/// at the tuned default threshold on realistic samples, (3) the exact
/// failing message from the original bug report is caught.
void main() {
  late Map<String, dynamic> fixtures;

  setUpAll(() {
    final modelPath = File('${Directory.current.path}/assets/spam_model.json');
    expect(
      modelPath.existsSync(),
      isTrue,
      reason: 'Run `python3 scripts/train_all_models.py` first',
    );
    SpamFilter.instance.engine.loadFromJsonStringForTest(modelPath.readAsStringSync());

    final fixturePath = File('${Directory.current.path}/test/fixtures/spam_fixtures.json');
    expect(
      fixturePath.existsSync(),
      isTrue,
      reason: 'Run `python3 scripts/generate_ml_fixtures.py` first',
    );
    fixtures = json.decode(fixturePath.readAsStringSync()) as Map<String, dynamic>;
  });

  test('model loads with realistic metadata', () {
    expect(SpamFilter.instance.isLoaded, isTrue);
    expect(SpamFilter.instance.defaultThreshold, inInclusiveRange(0.5, 1.0));
  });

  test('numerical parity with Python within 1e-4 across all fixtures', () {
    final cases = (fixtures['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThanOrEqualTo(10));
    for (final c in cases) {
      final text = c['text'] as String;
      final expected = (c['probability'] as num).toDouble();
      final actual = SpamFilter.instance.spamProbability(text);
      expect(
        (actual - expected).abs(),
        lessThan(1e-4),
        reason: 'Parity drift on "${text.length > 60 ? '${text.substring(0, 60)}…' : text}"',
      );
    }
  });

  test('every fixture is correctly classified at default threshold', () {
    final cases = (fixtures['cases'] as List).cast<Map<String, dynamic>>();
    final threshold = SpamFilter.instance.defaultThreshold;
    for (final c in cases) {
      final text = c['text'] as String;
      final label = c['label'] as String;
      final p = SpamFilter.instance.spamProbability(text);
      if (label == 'positive') {
        expect(p, greaterThanOrEqualTo(threshold),
            reason: 'Expected spam >= $threshold, got $p for "$text"');
      } else {
        expect(p, lessThan(threshold),
            reason: 'Expected ham < $threshold, got $p for "$text"');
      }
    }
  });

  test('original failing user message is detected as spam', () {
    const failing =
        'Your account has been credited with a Rs 3,000 bonus, '
        'available for withdrawal within 24 hours. Click: '
        'cutt.ly/StGmXhY1 NowAssignedL1RBPDA';
    expect(SpamFilter.instance.isSpam(failing), isTrue);
    expect(SpamFilter.instance.spamProbability(failing), greaterThan(0.9));
  });

  test('full corpus of real bank SMS is never flagged as spam', () {
    // If this fails after retraining the model is too aggressive.
    // These samples are drawn from the real data the user provided
    // and MUST stay well below the threshold.
    const legit = [
      // SBI (real data format)
      'Dear UPI user A/C X0587 debited by 500.00 on date 16Apr26 trf to SANDIP MANDAL Refno 300900907330 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI User, your A/c XXXXXX0587-credited by Rs.200.00 on 16-04-26 transfer from DIVYANSHUSINGH Ref No 200038012233 -SBI',
      'A/C X0587 debited by Rs.50.00 on 11Apr26 trf to M S SURINDER KUM Refno 602560907627 If not u? call-1800111109 for other services-18001234-SBI',
      // HDFC / ICICI / Axis / Kotak
      'Sent Rs.1200.00 From HDFC Bank A/C x1234 To AMAZON PAY On 10/04/26 Ref 204060010123 Not You? Call 18002586161/SMS BLOCK UPI to 7308080808',
      "You've received Rs 5000.00 in HDFC Bank A/c XX1234 via UPI from SURESH KUMAR on 10-Apr-26 Ref 204060010124",
      'ICICI Bank Acct XX123 debited for Rs 250.00 on 10-Apr-26; UPI:604123456789.',
      'INR 450.00 debited A/c no. XX1234 11-04-26 18:45:22 UPI/P2A/604123456791/ZOMATO. Bal INR 23,456.78.',
      'Kotak: Rs 199 debited from your Ac X0987 via UPI to swiggy@okaxis on 10-Apr-26. UPI Ref 604123456793.',
      // App-style
      'You paid Rs 250 to Zomato via UPI. UPI transaction ID 604123456800. From your Google Pay account.',
      'Payment of Rs.250 to swiggy@okhdfcbank successful. PhonePe. Txn ID T2304100012340',
      'Paytm: Received Rs 2000 from Priya. UPI ID priya@paytm. Txn ID 123456789012',
    ];
    for (final body in legit) {
      final p = SpamFilter.instance.spamProbability(body);
      expect(
        p,
        lessThan(SpamFilter.instance.defaultThreshold),
        reason: 'Legit bank SMS must not be filtered (p=$p): "$body"',
      );
    }
  });

  test('threshold override works', () {
    // A low-ish probability ham sample so an over-eager override to a very
    // high threshold reliably flips the answer to `false`.
    const hammy = 'Hey, can you pick up some milk on the way home?';
    expect(SpamFilter.instance.isSpam(hammy, threshold: 0.99), isFalse);
    // And a tiny threshold must flip a clearly-spam message to true.
    const scam =
        'Your account has been credited with a Rs 3,000 bonus, '
        'available for withdrawal within 24 hours. Click: cutt.ly/abc';
    expect(SpamFilter.instance.isSpam(scam, threshold: 0.10), isTrue);
  });

  test('empty / whitespace / unloaded are never flagged', () {
    expect(SpamFilter.instance.spamProbability(''), 0.0);
    expect(SpamFilter.instance.isSpam(''), isFalse);
    expect(SpamFilter.instance.isSpam('   '), isFalse);
  });
}
