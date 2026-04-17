import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/services/ml/classifiers.dart';

/// Direction classifier (debit vs credit) — layer 3 of the stack. Used as
/// a cross-check against the regex parser; the model is tiny (~34 KB) but
/// reaches perfect accuracy on the held-out split because the task is
/// dominated by a handful of keywords.
void main() {
  late Map<String, dynamic> fixtures;

  setUpAll(() {
    final modelPath = File('${Directory.current.path}/assets/direction_model.json');
    expect(modelPath.existsSync(), isTrue);
    DirectionClassifier.instance.engine.loadFromJsonStringForTest(
      modelPath.readAsStringSync(),
    );

    final fixturePath = File('${Directory.current.path}/test/fixtures/direction_fixtures.json');
    expect(fixturePath.existsSync(), isTrue);
    fixtures = json.decode(fixturePath.readAsStringSync()) as Map<String, dynamic>;
  });

  test('model loads', () {
    expect(DirectionClassifier.instance.isLoaded, isTrue);
  });

  test('numerical parity with Python within 1e-4', () {
    final cases = (fixtures['cases'] as List).cast<Map<String, dynamic>>();
    for (final c in cases) {
      final text = c['text'] as String;
      final expected = (c['probability'] as num).toDouble();
      final actual = DirectionClassifier.instance.creditProbability(text);
      expect((actual - expected).abs(), lessThan(1e-4),
          reason: 'drift on "${text.length > 60 ? '${text.substring(0, 60)}…' : text}"');
    }
  });

  test('every fixture classifies into the expected bucket', () {
    // label "positive" = credit, "negative" = debit
    final cases = (fixtures['cases'] as List).cast<Map<String, dynamic>>();
    for (final c in cases) {
      final text = c['text'] as String;
      final label = c['label'] as String;
      final p = DirectionClassifier.instance.creditProbability(text);
      if (label == 'positive') {
        expect(p, greaterThanOrEqualTo(0.5),
            reason: 'Expected credit (p>=0.5): "$text" — got $p');
      } else {
        expect(p, lessThan(0.5),
            reason: 'Expected debit (p<0.5): "$text" — got $p');
      }
    }
  });

  test('confident debits map to TxDirection.debit', () {
    const debits = [
      'Dear UPI user A/C X0587 debited by 500.00 on date 16Apr26 trf to SANDIP MANDAL Refno 300900907330',
      'Sent Rs.1200.00 From HDFC Bank A/C x1234 To AMAZON PAY On 10/04/26 Ref 204060010123',
      'ICICI Bank Acct XX123 debited for Rs 250.00 on 10-Apr-26; UPI:604123456789.',
      'You paid Rs 250 to Zomato via UPI. UPI transaction ID 604123456800.',
      'Paytm: Paid Rs 350 to Blinkit via UPI.',
    ];
    for (final body in debits) {
      expect(
        DirectionClassifier.instance.predict(body),
        TxDirection.debit,
        reason: 'Expected debit: "$body"',
      );
    }
  });

  test('confident credits map to TxDirection.credit', () {
    const credits = [
      'Dear UPI User, your A/c XXXXXX0587-credited by Rs.200.00 on 16-04-26 transfer from DIVYANSHUSINGH Ref No 200038012233 -SBI',
      "You've received Rs 5000.00 in HDFC Bank A/c XX1234 via UPI from SURESH KUMAR on 10-Apr-26",
      'You received Rs 500 from Rahul Sharma. Google Pay. UPI Ref: 604123456802',
      'Paytm: Received Rs 2000 from Priya.',
      'NEFT credit of Rs.25000 received in your A/c XX1234 on 10-04-26 from RAKESH KUMAR',
    ];
    for (final body in credits) {
      expect(
        DirectionClassifier.instance.predict(body),
        TxDirection.credit,
        reason: 'Expected credit: "$body"',
      );
    }
  });

  test('confidence band returns null for ambiguous input', () {
    // Use a confidence band so wide that nothing can satisfy it; the method
    // should respond with null (abstain) rather than guessing.
    final amb = DirectionClassifier.instance.predict(
      'hello world foo bar',
      confidence: 0.99,
    );
    expect(amb, isNull);
  });
}
