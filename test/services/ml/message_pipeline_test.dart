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

  group('PhonePe wallet / gift card and refund formats', () {
    // These real formats were dropped by the earlier models (the "Not you?
    // Call us … To top-up click <url>" wording looked like spam). They must
    // pass both layers now.
    test('wallet and gift card payments pass the full stack', () {
      const positives = [
        "You've paid Rs.207 via PhonePe gift card to SWIGGY on May 29, 2026 at 9:38:00 PM. Not you? Call us on 022-68727374. Remaining balance Rs.1534.",
        "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs. 3000. To top-up click https://phone.pe/PHONPE/ws",
        "You've paid Rs.100 via PhonePe wallet for City Mens Parlour. Not you? Call us on 022-68727374. Remaining balance: Rs.2187.5. To top-up click https://phone.pe/PHONPE/ws",
      ];
      for (final body in positives) {
        final d = MessagePipeline.instance.evaluate(body);
        expect(d.shouldIngest, isTrue, reason: 'pipeline dropped: $body → $d');
        expect(d.stage, 'passed');
      }
    });

    test('bank refund credits pass the full stack', () {
      const refunds = [
        'Dear Customer, For PAN XXXXXX123L, An IT Refund amount of Rs 11640 for AY-2026-27 has been credited to your account XXXXXXX1234 on 2026-07-11. -SBI',
        'Your A/C XXXX021234 has credit for ITDTAX REFUND 2026-27 LREPS480 of Rs 11,640.00 on 11/07/26. Avl Bal Rs 79,593.25.-SBI',
      ];
      for (final body in refunds) {
        final d = MessagePipeline.instance.evaluate(body);
        expect(d.shouldIngest, isTrue, reason: 'pipeline dropped: $body → $d');
        expect(d.directionHint, TxDirection.credit,
            reason: 'refund credit misdirected: $d');
      }
    });

    test('mandate creation / KYC / promos / fee offers still drop', () {
      const negatives = [
        'Your UPI-Mandate for Rs.139.00 is successfully created towards Spotify India Pvt Ltd from A/c No: XXXXXX1234. UMN:e728b5d9dd374742889f08faba01421e@ptyes. If not you, kindly report on 18001234. -SBI',
        'KYC record 10085682485845 for Rahul Kumar registered with Central KYC Registry has been updated by PhonePe Wallet on 06/Nov/2025.',
        "Dear User, You've earned Lifetime Free Kiwi UPI Credit Card (CC: JIOKIWI) on Jio Recharge. Claim now: https://t.jio/JIOCPN/WjSdc9 T&C* JioCoupons",
        '30145 is your one time password to proceed on PhonePe. It is valid for 10 minutes. Do not share your OTP with anyone.',
        'Monthly fee for your PhonePe device is Rs.125.00, with an offer pricing of Rs.1 subject to terms in PhonePe Business App. One-time set up fee is Rs.318.00 which includes first month Superstar Voice offer.',
        'Recharge successful! Plan: 349.0. Jio Number: 6290000000. Benefits: Unlimited 5G data, 56GB (2GB/Day 4G Data), Unlimited Voice, 100 SMS/Day. Validity - 28 Days. Transaction ID HGALP104740962550516.',
      ];
      for (final body in negatives) {
        final d = MessagePipeline.instance.evaluate(body);
        expect(d.shouldIngest, isFalse,
            reason: 'non-transaction slipped through: $body → $d');
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

  group('settlement evidence (RRN + settlement verb)', () {
    // Template the classifiers drop on their own (p_tx ≈ 0.42) even though
    // it is a completed credit; synthetic values only.
    const credit =
        'Your A/c *1234 is credited with Rs.55.00 on 03-10-26 by ASHA RAO. '
        'RRN 217100000001. Available balance is Rs.900.00 -Indian Bank';

    test('a registered bank header with an RRN is never dropped', () {
      final d = MessagePipeline.instance.evaluate(credit, sender: 'VM-INDBNK-S');
      expect(d.shouldIngest, isTrue);
      expect(d.reason, 'settlement-evidence');
    });

    test('the same text from a raw phone number gets no bypass', () {
      expect(
        MessagePipeline.hasSettlementEvidence(credit, sender: '+919800000000'),
        isFalse,
      );
      final d = MessagePipeline.instance.evaluate(credit, sender: '+919800000000');
      expect(d.reason, isNot('settlement-evidence'));
    });

    test('notifications (no sender) qualify on text alone', () {
      expect(
        MessagePipeline.hasSettlementEvidence(
            'Paid Rs.120 to Chai Point. UPI Ref No 512300000001'),
        isTrue,
      );
    });

    test('an RRN without a settlement verb is not evidence', () {
      expect(
        MessagePipeline.hasSettlementEvidence(
            'Your complaint RRN 217100000001 has been registered',
            sender: 'VM-INDBNK-S'),
        isFalse,
      );
    });

    test('a short reference number is not an RRN', () {
      expect(
        MessagePipeline.hasSettlementEvidence('Rs.10 credited. Ref No 12345',
            sender: 'VM-INDBNK-S'),
        isFalse,
      );
    });
  });
}
