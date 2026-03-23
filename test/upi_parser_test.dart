import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/transaction_record.dart';
import 'package:receipt/services/upi_parser.dart';

void main() {
  // =========================================================================
  // Real SBI SMS messages from user's phone (screenshots)
  // =========================================================================

  group('SBI Debit SMS (JD-SBIUPI-S / VA-SBIUPI-S)', () {
    test('debited by 50.00 trf to M S SURINDER KUM', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 50.00 on date 11Apr26 trf to M S SURINDER KUM Refno 602560907627 If not u? call-1800111109 for other services-18001234-SBI',
      );

      expect(parsed.isValid, isTrue, reason: 'Should be valid: $parsed');
      expect(parsed.amount, 50.00);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.counterpartyName, 'M S SURINDER KUM');
      expect(parsed.bankReference, '602560907627');
      expect(parsed.accountInfo, '****0587');
    });

    test('debited by 40.00 trf to MOHAMMAD ZAID', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 40.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614304676 If not u? call-1800111109 for other services-18001234-SBI',
      );

      expect(parsed.isValid, isTrue, reason: 'Should be valid: $parsed');
      expect(parsed.amount, 40.00);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.counterpartyName, 'MOHAMMAD ZAID');
      expect(parsed.bankReference, '300614304676');
      expect(parsed.accountInfo, '****0587');
    });

    test('debited by 18.83 trf to ADITI JHA', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 18.83 on date 14Apr26 trf to ADITI  JHA Refno 647083917725 If not u? call-1800111109 for other services-18001234-SBI',
      );

      expect(parsed.isValid, isTrue, reason: 'Should be valid: $parsed');
      expect(parsed.amount, 18.83);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.counterpartyName, contains('ADITI'));
      expect(parsed.counterpartyName, contains('JHA'));
      expect(parsed.bankReference, '647083917725');
    });

    test('debited by 20.00 trf to MOHAMMAD ZAID (VA sender)', () {
      final parsed = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969 If not u? call-1800111109 for other services-18001234-SBI',
      );

      expect(parsed.isValid, isTrue, reason: 'Should be valid: $parsed');
      expect(parsed.amount, 20.00);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.counterpartyName, 'MOHAMMAD ZAID');
      expect(parsed.bankReference, '300614399969');
    });
  });

  group('SBI Credit SMS (JD-SBIUPI-S / VA-SBIUPI-S)', () {
    test('credited by Rs.20.00 from TUMULURI ABHIRAM', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.20.00 on 10-04-26 transfer from TUMULURI ABHIRAM Ref No 610065050920 -SBI',
      );

      expect(parsed.isValid, isTrue, reason: 'Should be valid: $parsed');
      expect(parsed.amount, 20.00);
      expect(parsed.type, TransactionType.credit);
      expect(parsed.counterpartyName, 'TUMULURI ABHIRAM');
      expect(parsed.bankReference, '610065050920');
      expect(parsed.accountInfo, '****0587');
    });

    test('credited by Rs.280.00 from PANDEYNITINNAGENDRA', () {
      final parsed = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.280.00 on 13-04-26 transfer from PANDEYNITINNAGENDRA Ref No 175732878237 -SBI',
      );

      expect(parsed.isValid, isTrue, reason: 'Should be valid: $parsed');
      expect(parsed.amount, 280.00);
      expect(parsed.type, TransactionType.credit);
      expect(parsed.counterpartyName, 'PANDEYNITINNAGENDRA');
      expect(parsed.bankReference, '175732878237');
    });

    test('credited by Rs.1.00 from SARTHAK DNYANESHWAR YEOLE', () {
      final parsed = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.1.00 on 14-04-26 transfer from SARTHAK DNYANESHWAR YEOLE Ref No 610471232428 -SBI',
      );

      expect(parsed.isValid, isTrue, reason: 'Should be valid: $parsed');
      expect(parsed.amount, 1.00);
      expect(parsed.type, TransactionType.credit);
      expect(parsed.counterpartyName, 'SARTHAK DNYANESHWAR YEOLE');
      expect(parsed.bankReference, '610471232428');
    });
  });

  // =========================================================================
  // Sender identification
  // =========================================================================

  group('Sender identification', () {
    test('SBI sender codes', () {
      expect(UpiParser.identifyAppFromSender('JD-SBIUPI-S'), 'sbi');
      expect(UpiParser.identifyAppFromSender('VA-SBIUPI-S'), 'sbi');
      expect(UpiParser.identifyAppFromSender('AD-SBIBNK'), 'sbi');
    });

    test('other bank sender codes', () {
      expect(UpiParser.identifyAppFromSender('BZ-HDFCBK'), 'hdfc');
      expect(UpiParser.identifyAppFromSender('JD-ICICIB'), 'icici');
      expect(UpiParser.identifyAppFromSender('VM-AXISBK'), 'axis');
    });

    test('UPI app senders', () {
      expect(UpiParser.identifyAppFromSender('BT-GPAYTM'), 'gpay');
      expect(UpiParser.identifyAppFromSender('JD-PAYTM'), 'paytm');
      expect(UpiParser.identifyAppFromSender('BZ-PHONEPE'), 'phonepe');
    });

    test('unknown sender falls back to null', () {
      expect(UpiParser.identifyAppFromSender('randomsender'), isNull);
    });
  });

  // =========================================================================
  // isUpiRelated filter
  // =========================================================================

  group('isUpiRelated', () {
    test('detects SBI debit messages', () {
      expect(UpiParser.isUpiRelated(
        'Dear UPI user A/C X0587 debited by 50.00 on date 11Apr26 trf to M S SURINDER KUM Refno 602560907627',
      ), isTrue);
    });

    test('detects SBI credit messages', () {
      expect(UpiParser.isUpiRelated(
        'Dear UPI User, your A/c XXXXXX0587-credited by Rs.20.00 on 10-04-26 transfer from TUMULURI ABHIRAM Ref No 610065050920 -SBI',
      ), isTrue);
    });

    test('rejects unrelated messages', () {
      expect(UpiParser.isUpiRelated('Your OTP is 123456'), isFalse);
      expect(UpiParser.isUpiRelated('Sale at Flipkart! 50% off'), isFalse);
      expect(UpiParser.isUpiRelated('Your parcel has been shipped'), isFalse);
    });
  });

  // =========================================================================
  // Amount extraction edge cases
  // =========================================================================

  group('Amount extraction', () {
    test('bare number after "debited by"', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 1250.50 on date 14Apr26 trf to SOMEONE Refno 123456789012',
      );
      expect(parsed.amount, 1250.50);
    });

    test('Rs. prefixed after "credited by"', () {
      final parsed = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.5000.00 on 14-04-26 transfer from SOMEONE Ref No 123456789012 -SBI',
      );
      expect(parsed.amount, 5000.00);
    });

    test('₹ symbol amounts', () {
      final parsed = UpiParser.parseSms(
        sender: 'BT-GPAY',
        body: 'You paid ₹500.00 to John Doe via UPI',
      );
      expect(parsed.amount, 500.00);
    });

    test('comma-separated large amounts', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 1,50,000.00 on date 14Apr26 trf to SOMEONE Refno 123456789012',
      );
      expect(parsed.amount, 150000.00);
    });
  });

  // =========================================================================
  // Deduplication: same payment from different sources
  // =========================================================================

  group('Dedup - same payment different senders', () {
    test('same debit from JD and VA sender both parse to same ref', () {
      final p1 = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969 If not u? call-1800111109 for other services-18001234-SBI',
      );
      final p2 = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969 If not u? call-1800111109 for other services-18001234-SBI',
      );

      expect(p1.bankReference, p2.bankReference);
      expect(p1.amount, p2.amount);
      expect(p1.counterpartyName, p2.counterpartyName);
    });
  });

  // =========================================================================
  // Other bank formats (GPay, PhonePe, Paytm, HDFC, ICICI)
  // =========================================================================

  group('GPay notification format', () {
    test('paid to someone', () {
      final parsed = UpiParser.parseNotification(
        packageName: 'com.google.android.apps.nbu.paisa.user',
        title: 'Payment sent',
        text: 'Paid ₹500 to John Doe',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 500.0);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.upiApp, 'gpay');
    });

    test('received from someone', () {
      final parsed = UpiParser.parseNotification(
        packageName: 'com.google.android.apps.nbu.paisa.user',
        title: 'Payment received',
        text: 'Received ₹200 from Jane Smith',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 200.0);
      expect(parsed.type, TransactionType.credit);
    });
  });

  group('PhonePe notification format', () {
    test('payment successful', () {
      final parsed = UpiParser.parseNotification(
        packageName: 'com.phonepe.app',
        title: 'PhonePe',
        text: 'Payment of Rs.350 to Swiggy successful. UPI Ref No 412345678901',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 350.0);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.upiApp, 'phonepe');
    });
  });

  group('HDFC bank SMS format', () {
    test('account debited', () {
      final parsed = UpiParser.parseSms(
        sender: 'BZ-HDFCBK',
        body: 'Your A/c XXXX1234 is debited for Rs.2500.00 on 14-04-26. UPI Ref No 412345678901. Avl bal Rs.15000.00',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 2500.00);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.bankReference, '412345678901');
    });
  });

  // =========================================================================
  // Reference extraction
  // =========================================================================

  group('Reference extraction', () {
    test('Refno (no space)', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 50.00 on date 11Apr26 trf to SOMEONE Refno 602560907627',
      );
      expect(parsed.bankReference, '602560907627');
    });

    test('Ref No (with space)', () {
      final parsed = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.20.00 on 10-04-26 transfer from SOMEONE Ref No 610065050920 -SBI',
      );
      expect(parsed.bankReference, '610065050920');
    });

    test('UPI Ref No', () {
      final parsed = UpiParser.parseSms(
        sender: 'BZ-HDFCBK',
        body: 'Your A/c debited Rs.500. UPI Ref No 412345678901',
      );
      expect(parsed.bankReference, '412345678901');
    });
  });

  // =========================================================================
  // Account extraction
  // =========================================================================

  group('Account extraction', () {
    test('A/C X0587 format', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 50.00 on date 11Apr26 trf to SOMEONE Refno 123456789012',
      );
      expect(parsed.accountInfo, '****0587');
    });

    test('A/c XXXXXX0587 format', () {
      final parsed = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.20.00 on 10-04-26 transfer from SOMEONE Ref No 123456789012 -SBI',
      );
      expect(parsed.accountInfo, '****0587');
    });

    test('A/c XXXX1234 format', () {
      final parsed = UpiParser.parseSms(
        sender: 'BZ-HDFCBK',
        body: 'Your A/c XXXX1234 is debited for Rs.500 on 14-04-26. UPI Ref No 123456789012',
      );
      expect(parsed.accountInfo, '****1234');
    });
  });

  // =========================================================================
  // Validity — messages that should NOT parse
  // =========================================================================

  group('Invalid / non-UPI messages', () {
    test('OTP message returns invalid', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIBNK',
        body: 'Your OTP for transaction is 856432. Do not share with anyone.',
      );
      expect(parsed.isValid, isFalse);
    });

    test('promo message returns invalid', () {
      final parsed = UpiParser.parseSms(
        sender: 'BZ-AMAZON',
        body: 'Big sale on Amazon! Up to 70% off on electronics. Shop now.',
      );
      expect(parsed.isValid, isFalse);
    });
  });
}
