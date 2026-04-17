import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/transaction_record.dart';
import 'package:receipt/services/ml/classifiers.dart';
import 'package:receipt/services/ml/message_pipeline.dart';
import 'package:receipt/services/upi_parser.dart';

/// Integration test that mirrors the exact gate used by the provider in
/// `_handleSms` and `scanSmsHistory`:
///
///   1. cheap UPI keyword filter      (UpiParser.isUpiRelated)
///   2. MessagePipeline.evaluate      (spam → transactional → direction)
///   3. UpiParser.parseSms (+ isValid) to extract amount, type, name, etc.
///
/// Passes iff all three agree. Guards the "don't drop real txns" and
/// "never record a spam credit" contracts end-to-end.
void main() {
  setUpAll(() {
    void loadInto(dynamic cls, String path) {
      final f = File('${Directory.current.path}/$path');
      expect(f.existsSync(), isTrue);
      cls.engine.loadFromJsonStringForTest(f.readAsStringSync());
    }

    loadInto(SpamFilter.instance, 'assets/spam_model.json');
    loadInto(TransactionalClassifier.instance, 'assets/transactional_model.json');
    loadInto(DirectionClassifier.instance, 'assets/direction_model.json');
  });

  ({bool ingest, String stage}) runGate(String sender, String body) {
    if (!UpiParser.isUpiRelated(body)) return (ingest: false, stage: 'keyword');
    final decision = MessagePipeline.instance.evaluate(body);
    if (!decision.shouldIngest) return (ingest: false, stage: decision.stage);
    final parsed = UpiParser.parseSms(sender: sender, body: body);
    if (!parsed.isValid) return (ingest: false, stage: 'parser');
    return (ingest: true, stage: 'passed');
  }

  group('gate rejects promotional / scam messages', () {
    test('the original failing user bug — "bonus credited"', () {
      const body =
          'Your account has been credited with a Rs 3,000 bonus, '
          'available for withdrawal within 24 hours. Click: '
          'cutt.ly/StGmXhY1 NowAssignedL1RBPDA';
      // Without the stack: isUpiRelated=true and parser would extract
      // Rs 3,000 credit → bogus record. The stack must drop it.
      expect(UpiParser.isUpiRelated(body), isTrue);
      expect(UpiParser.parseSms(sender: 'VM-BONUS', body: body).isValid, isTrue);
      final r = runGate('VM-BONUS', body);
      expect(r.ingest, isFalse);
      expect(r.stage, 'spam');
    });

    test('Indian scam / phishing samples are blocked', () {
      const samples = [
        'CONGRATULATIONS! FREE 2GB data is yours! Claim on Airtel Thanks App Now. Hurry i.airtel.in/e/csl_ml_2GB',
        'You have won Rs 5,000 cashback. Click here to claim: http://win.example.com/claim',
        'URGENT: Your KYC has expired. Update OTP at axis-secure.link now to avoid block',
        'You are selected for a Rs 1 crore lottery. Send your bank details to claim@win.co',
      ];
      for (final body in samples) {
        final r = runGate('VM-SPAM', body);
        expect(r.ingest, isFalse, reason: 'must drop: $body');
      }
    });
  });

  group('gate rejects non-transactional banking messages', () {
    test('OTPs are rejected at the transactional stage', () {
      const body =
          'Dear Customer, 478912 is your OTP for transaction of Rs 500 '
          'on HDFC card ending 1234. Do not share. Valid for 5 min.';
      final r = runGate('HDFCBK', body);
      expect(r.ingest, isFalse);
      expect(r.stage, 'transactional');
    });

    test('failed transactions and balance alerts are rejected', () {
      const samples = [
        'Dear Customer, your UPI payment of Rs 500 to merchant@upi on 10-04-26 FAILED. Any amount debited will be reversed in 3-5 days. -SBI',
        'Your A/c XX0587 balance is Rs 3,245.67 as on 12-04-26 17:00. -SBI',
        'Your transaction of Rs 250 on card XX1234 was DECLINED on 10-04-26. -HDFC',
      ];
      for (final body in samples) {
        final r = runGate('BANKSM', body);
        expect(r.ingest, isFalse, reason: 'must drop non-tx: $body');
      }
    });
  });

  group('gate passes legitimate UPI transactions', () {
    test('real SBI debit / credit SMS are ingested with correct direction', () {
      const sampleDebits = [
        'Dear UPI user A/C X0587 debited by 500.00 on date 16Apr26 trf to SANDIP MANDAL Refno 300900907330 If not u? call-1800111109 for other services-18001234-SBI',
        'Dear UPI user A/C X0587 debited by 20.00 on date 06Apr26 trf to Universal Grocer Refno 300264030291 If not u? call-1800111109 for other services-18001234-SBI',
      ];
      for (final body in sampleDebits) {
        final r = runGate('SBIINB', body);
        expect(r.ingest, isTrue, reason: 'debit must ingest: $body');
        final parsed = UpiParser.parseSms(sender: 'SBIINB', body: body);
        expect(parsed.type, TransactionType.debit);
      }

      const sampleCredits = [
        'Dear UPI User, your A/c XXXXXX0587-credited by Rs.200.00 on 16-04-26 transfer from DIVYANSHUSINGH Ref No 200038012233 -SBI',
        'Dear UPI User, your A/c XXXXXX0587-credited by Rs.900.00 on 03-01-26 transfer from Subarna Sen Ref No 600350194136 -SBI',
      ];
      for (final body in sampleCredits) {
        final r = runGate('SBIINB', body);
        expect(r.ingest, isTrue, reason: 'credit must ingest: $body');
        final parsed = UpiParser.parseSms(sender: 'SBIINB', body: body);
        expect(parsed.type, TransactionType.credit);
      }
    });

    test('HDFC / ICICI / Axis / Kotak transactional SMS are ingested', () {
      const samples = {
        'HDFCBK': 'Sent Rs.1200.00 From HDFC Bank A/C x1234 To AMAZON PAY On 10/04/26 Ref 204060010123 Not You? Call 18002586161',
        'ICICIB': 'ICICI Bank Acct XX123 debited for Rs 250.00 on 10-Apr-26; UPI:604123456789.',
        'AXISBK': 'INR 450.00 debited A/c no. XX1234 11-04-26 18:45:22 UPI/P2A/604123456791/ZOMATO. Bal INR 23,456.78.',
        'KOTAKB': 'Kotak: Rs 199 debited from your Ac X0987 via UPI to swiggy@okaxis on 10-Apr-26. UPI Ref 604123456793.',
      };
      samples.forEach((sender, body) {
        final r = runGate(sender, body);
        expect(r.ingest, isTrue, reason: '$sender must ingest: $body');
      });
    });

    test('GPay / PhonePe / Paytm style notifications pass through', () {
      const samples = [
        'You paid Rs 250 to Zomato via UPI. UPI transaction ID 604123456800. From your Google Pay account.',
        'Payment of Rs.250 to swiggy@okhdfcbank successful. PhonePe. Txn ID T2304100012340',
        'Paytm: Paid Rs 350 to Blinkit via UPI. Order ID OID0987654321',
        'Paytm: Received Rs 2000 from Priya. UPI ID priya@paytm. Txn ID 123456789012',
      ];
      for (final body in samples) {
        final r = runGate('VK-UPIAPP', body);
        expect(r.ingest, isTrue, reason: 'must ingest: $body');
      }
    });
  });

  test('large sample from user data/upi*.csv survives end-to-end', () {
    // Mix of real debits and credits pulled straight from the user's data.
    // The whole stack must pass every one of them. If this ever breaks,
    // real transactions are being lost and the stack needs retraining.
    const real = [
      'Dear UPI user A/C X0587 debited by 500.00 on date 16Apr26 trf to SANDIP MANDAL Refno 300900907330 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI User, your A/c XXXXXX0587-credited by Rs.200.00 on 16-04-26 transfer from DIVYANSHUSINGH Ref No 200038012233 -SBI',
      'Dear UPI user A/C X0587 debited by 10.00 on date 06Apr26 trf to Universal Grocer Refno 300264030291 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI User, your A/c XXXXXX0587-credited by Rs.50.00 on 02-04-26 transfer from Mr Giddaluri Suseel Kumar Ref No 854125065301 -SBI',
      'Dear UPI user A/C X0587 debited by 118.00 on date 01Apr26 trf to JITENDRA Refno 203084223330 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI user A/C X0587 debited by 170.00 on date 28Mar26 trf to OJAS CATERING SE Refno 601765065803 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI user A/C X0587 debited by 266.76 on date 26Mar26 trf to Fresh Signature Refno 601633966118 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI user A/C X0587 debited by 205.53 on date 26Mar26 trf to ZOMATO Refno 175340016675 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI User, your A/c XXXXXX0587-credited by Rs.80.00 on 26-03-26 transfer from SHASHANK  YADAV Ref No 608555622488 -SBI',
      'Dear UPI user A/C X0587 debited by 40.00 on date 24Mar26 trf to MOHAMMAD ZAID Refno 399491858303 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI user A/C X0587 debited by 350.80 on date 20Mar26 trf to Jio Refno 202296724981 If not u? call-1800111109 for other services-18001234-SBI',
      'Dear UPI User, your A/c XXXXXX0587-credited by Rs.900.00 on 03-01-26 transfer from Subarna Sen Ref No 600350194136 -SBI',
    ];
    for (final body in real) {
      final r = runGate('SBIINB', body);
      expect(r.ingest, isTrue, reason: 'real user SMS dropped at ${r.stage}: $body');
    }
  });
}
