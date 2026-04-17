import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/transaction_record.dart';
import 'package:receipt/services/ml/classifiers.dart';
import 'package:receipt/services/ml/message_pipeline.dart';

/// Tests the stacked [MessagePipeline] orchestration using the real shipped
/// models. Verifies the short-circuit semantics (spam → transactional →
/// passed) as well as the downstream direction-hint / disagreement logic
/// used by the provider to sanity-check the regex parser.
void main() {
  setUpAll(() {
    void loadInto(dynamic cls, String path) {
      final f = File('${Directory.current.path}/$path');
      expect(f.existsSync(), isTrue, reason: '$path missing — run trainer');
      cls.engine.loadFromJsonStringForTest(f.readAsStringSync());
    }

    loadInto(SpamFilter.instance, 'assets/spam_model.json');
    loadInto(TransactionalClassifier.instance, 'assets/transactional_model.json');
    loadInto(DirectionClassifier.instance, 'assets/direction_model.json');
  });

  group('stage short-circuiting', () {
    test('spam messages are dropped at the spam stage', () {
      const body =
          'Your account has been credited with a Rs 3,000 bonus, '
          'available for withdrawal within 24 hours. Click: '
          'cutt.ly/StGmXhY1 NowAssignedL1RBPDA';
      final d = MessagePipeline.instance.evaluate(body);
      expect(d.shouldIngest, isFalse);
      expect(d.stage, 'spam');
      expect(d.spamProbability, greaterThan(0.85));
    });

    test('OTPs drop at the transactional stage (not spam)', () {
      const otp =
          'Dear Customer, 478912 is your OTP for transaction of Rs 500 '
          'on HDFC card ending 1234. Do not share. Valid for 5 min.';
      final d = MessagePipeline.instance.evaluate(otp);
      expect(d.shouldIngest, isFalse);
      expect(d.stage, 'transactional');
      expect(d.spamProbability, lessThan(0.85));
      expect(d.transactionalProbability, lessThan(0.5));
    });

    test('failed / declined transactions drop at the transactional stage', () {
      const failed =
          'Dear Customer, your UPI payment of Rs 500 to merchant@upi on '
          '10-04-26 FAILED. Any amount debited will be reversed in 3-5 '
          'days. -SBI';
      final d = MessagePipeline.instance.evaluate(failed);
      expect(d.shouldIngest, isFalse);
      expect(d.stage, 'transactional');
    });

    test('balance alerts drop at the transactional stage', () {
      const balance = 'Your A/c XX0587 balance is Rs 3,245.67 as on 12-04-26 17:00. -SBI';
      final d = MessagePipeline.instance.evaluate(balance);
      expect(d.shouldIngest, isFalse);
      expect(d.stage, 'transactional');
    });

    test('real UPI transactions pass through', () {
      const samples = [
        // real SBI debit / credit from the user's data
        'Dear UPI user A/C X0587 debited by 500.00 on date 16Apr26 trf to SANDIP MANDAL Refno 300900907330 If not u? call-1800111109 for other services-18001234-SBI',
        'Dear UPI User, your A/c XXXXXX0587-credited by Rs.200.00 on 16-04-26 transfer from DIVYANSHUSINGH Ref No 200038012233 -SBI',
        // other banks
        'Sent Rs.1200.00 From HDFC Bank A/C x1234 To AMAZON PAY On 10/04/26 Ref 204060010123',
        'ICICI Bank Acct XX123 debited for Rs 250.00 on 10-Apr-26; UPI:604123456789.',
        'You paid Rs 250 to Zomato via UPI. UPI transaction ID 604123456800.',
        'Paytm: Received Rs 2000 from Priya. UPI ID priya@paytm. Txn ID 123456789012',
      ];
      for (final body in samples) {
        final d = MessagePipeline.instance.evaluate(body);
        expect(d.shouldIngest, isTrue, reason: 'pipeline dropped: $body → $d');
        expect(d.stage, 'passed');
      }
    });
  });

  group('direction hint', () {
    test('passes through a debit hint on real SBI debit SMS', () {
      const body =
          'Dear UPI user A/C X0587 debited by 500.00 on date 16Apr26 trf '
          'to SANDIP MANDAL Refno 300900907330';
      final d = MessagePipeline.instance.evaluate(body);
      expect(d.shouldIngest, isTrue);
      expect(d.directionHint, TxDirection.debit);
      expect(d.creditProbability, isNotNull);
      expect(d.creditProbability!, lessThan(0.35));
    });

    test('passes through a credit hint on real SBI credit SMS', () {
      const body =
          'Dear UPI User, your A/c XXXXXX0587-credited by Rs.200.00 on '
          '16-04-26 transfer from DIVYANSHUSINGH Ref No 200038012233 -SBI';
      final d = MessagePipeline.instance.evaluate(body);
      expect(d.shouldIngest, isTrue);
      expect(d.directionHint, TxDirection.credit);
      expect(d.creditProbability, isNotNull);
      expect(d.creditProbability!, greaterThan(0.65));
    });

    test('disagreesWithParser returns true only on actual mismatches', () {
      const debitBody =
          'Dear UPI user A/C X0587 debited by 500.00 on date 16Apr26 trf '
          'to SANDIP MANDAL Refno 300900907330';
      final d = MessagePipeline.instance.evaluate(debitBody);
      expect(d.disagreesWithParser(TransactionType.debit), isFalse);
      expect(d.disagreesWithParser(TransactionType.credit), isTrue);
      expect(d.disagreesWithParser(null), isFalse);
    });
  });

  test('a full batch of real SBI messages from the user\'s data ingests', () {
    // Sampled from data/upi1.csv — these are all real transactions. The
    // whole stack must classify every one of them as `shouldIngest: true`
    // at the tuned thresholds, with the correct direction hint.
    const real = [
      'Dear UPI user A/C X0587 debited by 20.00 on date 16Apr26 trf to Pitamber Paudel Refno 204159809704 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI user A/C X0587 debited by 140.00 on date 16Apr26 trf to New Indore sav b Refno 602899121852 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI User, your A/c XXXXXX0587-credited by Rs.60.00 on 16-04-26 transfer from VINUKONDA ABHINOV Ref No 610606886225 -SBI',
      'Dear UPI User, your A/c XXXXXX0587-credited by Rs.80.00 on 16-04-26 transfer from Mr SHAHRUKH  KHA Ref No 300894256967 -SBI',
      'Dear UPI user A/C X0587 debited by 350.80 on date 20Mar26 trf to Jio Refno 202296724981 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI User, your A/c XXXXXX0587-credited by Rs.900.00 on 03-01-26 transfer from Subarna Sen Ref No 600350194136 -SBI',
    ];
    for (final body in real) {
      final d = MessagePipeline.instance.evaluate(body);
      expect(d.shouldIngest, isTrue,
          reason: 'real SBI SMS rejected by pipeline: $d — "$body"');
      final expectedDir = body.contains('credited') ? TxDirection.credit : TxDirection.debit;
      expect(d.directionHint, expectedDir,
          reason: 'wrong direction hint for "$body" → $d');
    }
  });
}
