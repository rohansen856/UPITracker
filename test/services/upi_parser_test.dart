import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/transaction_record.dart';
import 'package:receipt/services/upi_parser.dart';

void main() {
  // ===========================================================================
  // ParsedUpi model
  // ===========================================================================

  group('ParsedUpi', () {
    test('isValid requires positive amount and non-null type', () {
      expect(ParsedUpi(amount: 100, type: TransactionType.debit).isValid, isTrue);
      expect(ParsedUpi(amount: 0, type: TransactionType.debit).isValid, isFalse);
      expect(ParsedUpi(amount: -5, type: TransactionType.debit).isValid, isFalse);
      expect(ParsedUpi(amount: 100, type: null).isValid, isFalse);
      expect(ParsedUpi(amount: null, type: TransactionType.debit).isValid, isFalse);
      expect(ParsedUpi().isValid, isFalse);
    });

    test('toString includes key fields', () {
      final p = ParsedUpi(amount: 500, type: TransactionType.debit, counterpartyName: 'John');
      expect(p.toString(), contains('500'));
      expect(p.toString(), contains('John'));
    });
  });

  // ===========================================================================
  // identifyAppFromPackage
  // ===========================================================================

  group('identifyAppFromPackage', () {
    test('maps all known packages', () {
      final cases = {
        'com.google.android.apps.nbu.paisa.user': 'gpay',
        'net.one97.paytm': 'paytm',
        'com.phonepe.app': 'phonepe',
        'in.org.npci.upiapp': 'bhim',
        'com.whatsapp': 'whatsapp',
        'com.amazon.mShop.android.shopping': 'amazon',
        'com.mobikwik_new': 'mobikwik',
        'com.freecharge.android': 'freecharge',
        'com.myairtel.myairtelapp': 'airtel',
        'com.jio.myjio': 'jio',
      };
      for (final entry in cases.entries) {
        expect(UpiParser.identifyAppFromPackage(entry.key), entry.value, reason: 'Failed for ${entry.key}');
      }
    });

    test('returns null for unknown package', () {
      expect(UpiParser.identifyAppFromPackage('com.unknown.app'), isNull);
    });
  });

  // ===========================================================================
  // identifyAppFromSender
  // ===========================================================================

  group('identifyAppFromSender', () {
    test('SBI sender codes', () {
      expect(UpiParser.identifyAppFromSender('JD-SBIUPI-S'), 'sbi');
      expect(UpiParser.identifyAppFromSender('VA-SBIUPI-S'), 'sbi');
      expect(UpiParser.identifyAppFromSender('AD-SBIBNK'), 'sbi');
    });

    test('other bank sender codes', () {
      expect(UpiParser.identifyAppFromSender('BZ-HDFCBK'), 'hdfc');
      expect(UpiParser.identifyAppFromSender('JD-ICICIB'), 'icici');
      expect(UpiParser.identifyAppFromSender('VM-AXISBK'), 'axis');
      expect(UpiParser.identifyAppFromSender('BZ-BOBSMS'), 'bob');
      expect(UpiParser.identifyAppFromSender('JD-PNBSMS'), 'pnb');
      expect(UpiParser.identifyAppFromSender('VM-KOTAK'), 'kotak');
      expect(UpiParser.identifyAppFromSender('JD-UNIONBK'), 'union');
      expect(UpiParser.identifyAppFromSender('VM-CANARA'), 'canara');
      expect(UpiParser.identifyAppFromSender('BZ-INDIANBK'), 'indianbank');
    });

    test('UPI app senders', () {
      expect(UpiParser.identifyAppFromSender('BT-GPAYTM'), 'gpay');
      expect(UpiParser.identifyAppFromSender('JD-PAYTM'), 'paytm');
      expect(UpiParser.identifyAppFromSender('BZ-PHONEPE'), 'phonepe');
    });

    test('case-insensitive', () {
      expect(UpiParser.identifyAppFromSender('jd-sbiupi-s'), 'sbi');
      expect(UpiParser.identifyAppFromSender('Bz-Hdfcbk'), 'hdfc');
    });

    test('unknown sender returns null', () {
      expect(UpiParser.identifyAppFromSender('randomsender'), isNull);
      expect(UpiParser.identifyAppFromSender('XX-YYYYYY'), isNull);
    });
  });

  // ===========================================================================
  // Real SBI SMS messages
  // ===========================================================================

  group('SBI Debit SMS', () {
    test('debited by 50.00 trf to M S SURINDER KUM', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 50.00 on date 11Apr26 trf to M S SURINDER KUM Refno 602560907627 If not u? call-1800111109 for other services-18001234-SBI',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 50.00);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.counterpartyName, 'M S SURINDER KUM');
      expect(parsed.bankReference, '602560907627');
      expect(parsed.accountInfo, '****0587');
      expect(parsed.upiApp, 'sbi');
    });

    test('debited by 40.00 trf to MOHAMMAD ZAID', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 40.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614304676 If not u? call-1800111109 for other services-18001234-SBI',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 40.00);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.counterpartyName, 'MOHAMMAD ZAID');
      expect(parsed.bankReference, '300614304676');
    });

    test('debited by 18.83 trf to ADITI  JHA', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 18.83 on date 14Apr26 trf to ADITI  JHA Refno 647083917725 If not u? call-1800111109 for other services-18001234-SBI',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 18.83);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.counterpartyName, contains('ADITI'));
      expect(parsed.counterpartyName, contains('JHA'));
      expect(parsed.bankReference, '647083917725');
    });

    test('VA sender variant', () {
      final parsed = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969 If not u? call-1800111109 for other services-18001234-SBI',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 20.00);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.counterpartyName, 'MOHAMMAD ZAID');
      expect(parsed.bankReference, '300614399969');
    });
  });

  group('SBI Credit SMS', () {
    test('credited by Rs.20.00 from TUMULURI ABHIRAM', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.20.00 on 10-04-26 transfer from TUMULURI ABHIRAM Ref No 610065050920 -SBI',
      );
      expect(parsed.isValid, isTrue);
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
      expect(parsed.isValid, isTrue);
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
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 1.00);
      expect(parsed.type, TransactionType.credit);
      expect(parsed.counterpartyName, 'SARTHAK DNYANESHWAR YEOLE');
      expect(parsed.bankReference, '610471232428');
    });
  });

  // ===========================================================================
  // GPay Notification Format
  // ===========================================================================

  group('GPay notification', () {
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

  // ===========================================================================
  // PhonePe Notification Format
  // ===========================================================================

  group('PhonePe notification', () {
    test('payment successful with UPI ref', () {
      final parsed = UpiParser.parseNotification(
        packageName: 'com.phonepe.app',
        title: 'PhonePe',
        text: 'Payment of Rs.350 to Swiggy successful. UPI Ref No 412345678901',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 350.0);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.upiApp, 'phonepe');
      expect(parsed.bankReference, '412345678901');
    });
  });

  // ===========================================================================
  // HDFC Bank SMS
  // ===========================================================================

  group('HDFC bank SMS', () {
    test('account debited', () {
      final parsed = UpiParser.parseSms(
        sender: 'BZ-HDFCBK',
        body: 'Your A/c XXXX1234 is debited for Rs.2500.00 on 14-04-26. UPI Ref No 412345678901. Avl bal Rs.15000.00',
      );
      expect(parsed.isValid, isTrue);
      expect(parsed.amount, 2500.00);
      expect(parsed.type, TransactionType.debit);
      expect(parsed.bankReference, '412345678901');
      expect(parsed.accountInfo, '****1234');
      expect(parsed.upiApp, 'hdfc');
    });
  });

  // ===========================================================================
  // Type detection
  // ===========================================================================

  group('Transaction type detection', () {
    test('detects credit keywords', () {
      for (final kw in ['credited', 'received', 'refund', 'cashback']) {
        final parsed = UpiParser.parseSms(sender: 'XX-BANK', body: 'Your account $kw Rs.100');
        expect(parsed.type, TransactionType.credit, reason: 'Failed for keyword: $kw');
      }
    });

    test('detects debit keywords', () {
      for (final kw in ['debited', 'paid', 'sent', 'transferred', 'purchase']) {
        final parsed = UpiParser.parseSms(sender: 'XX-BANK', body: 'Your account $kw Rs.100');
        expect(parsed.type, TransactionType.debit, reason: 'Failed for keyword: $kw');
      }
    });

    test('"trf to" is detected as debit', () {
      final parsed = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'A/C X0587 debited by 50.00 trf to SOMEONE Refno 123456789012',
      );
      expect(parsed.type, TransactionType.debit);
    });
  });

  // ===========================================================================
  // Amount extraction
  // ===========================================================================

  group('Amount extraction', () {
    test('₹ symbol amount', () {
      final p = UpiParser.parseSms(sender: 'BT-GPAY', body: 'You paid ₹500.00 to John via UPI');
      expect(p.amount, 500.00);
    });

    test('Rs. prefixed amount', () {
      final p = UpiParser.parseSms(sender: 'VA-SBIUPI-S', body: 'credited by Rs.5000.00 on 14-04-26 transfer from SOMEONE Ref No 123456789012 -SBI');
      expect(p.amount, 5000.00);
    });

    test('bare number after "debited by"', () {
      final p = UpiParser.parseSms(sender: 'JD-SBIUPI-S', body: 'A/C X0587 debited by 1250.50 trf to SOMEONE Refno 123456789012');
      expect(p.amount, 1250.50);
    });

    test('comma-separated large amounts', () {
      final p = UpiParser.parseSms(sender: 'JD-SBIUPI-S', body: 'debited by 1,50,000.00 trf to SOMEONE Refno 123456789012');
      expect(p.amount, 150000.00);
    });

    test('INR prefixed amount', () {
      final p = UpiParser.parseSms(sender: 'XX-BANK', body: 'Account debited INR 750.00');
      expect(p.amount, 750.00);
    });

    test('zero amount returns null (invalid)', () {
      final p = UpiParser.parseSms(sender: 'XX-BANK', body: 'debited Rs.0.00');
      expect(p.amount, isNull);
    });
  });

  // ===========================================================================
  // Reference extraction
  // ===========================================================================

  group('Reference extraction', () {
    test('Refno (no space)', () {
      final p = UpiParser.parseSms(sender: 'JD-SBIUPI-S', body: 'debited by 50.00 trf to SOMEONE Refno 602560907627');
      expect(p.bankReference, '602560907627');
    });

    test('Ref No (with space)', () {
      final p = UpiParser.parseSms(sender: 'VA-SBIUPI-S', body: 'credited by Rs.20.00 transfer from SOMEONE Ref No 610065050920 -SBI');
      expect(p.bankReference, '610065050920');
    });

    test('UPI Ref No', () {
      final p = UpiParser.parseSms(sender: 'BZ-HDFCBK', body: 'A/c debited Rs.500. UPI Ref No 412345678901');
      expect(p.bankReference, '412345678901');
    });

    test('no reference returns null', () {
      final p = UpiParser.parseSms(sender: 'BT-GPAY', body: 'You paid ₹100 to John');
      expect(p.bankReference, isNull);
    });
  });

  // ===========================================================================
  // Account extraction
  // ===========================================================================

  group('Account extraction', () {
    test('A/C X0587 format', () {
      final p = UpiParser.parseSms(sender: 'JD-SBIUPI-S', body: 'A/C X0587 debited by 50.00 trf to SOMEONE Refno 123456789012');
      expect(p.accountInfo, '****0587');
    });

    test('A/c XXXXXX0587 format', () {
      final p = UpiParser.parseSms(sender: 'VA-SBIUPI-S', body: 'A/c XXXXXX0587-credited by Rs.20.00 transfer from SOMEONE Ref No 123456789012 -SBI');
      expect(p.accountInfo, '****0587');
    });

    test('A/c XXXX1234 format', () {
      final p = UpiParser.parseSms(sender: 'BZ-HDFCBK', body: 'Your A/c XXXX1234 is debited for Rs.500 UPI Ref No 123456789012');
      expect(p.accountInfo, '****1234');
    });

    test('no account info returns null', () {
      final p = UpiParser.parseSms(sender: 'BT-GPAY', body: 'You paid ₹100 to John');
      expect(p.accountInfo, isNull);
    });
  });

  // ===========================================================================
  // UPI ID extraction
  // ===========================================================================

  group('UPI ID extraction', () {
    test('extracts @okaxis UPI IDs', () {
      final p = UpiParser.parseSms(sender: 'XX-BANK', body: 'Paid Rs.100 to john@okaxis via UPI');
      expect(p.counterpartyUpiId, 'john@okaxis');
    });

    test('extracts @ybl UPI IDs', () {
      final p = UpiParser.parseSms(sender: 'XX-BANK', body: 'Received Rs.200 from merchant@ybl');
      expect(p.counterpartyUpiId, 'merchant@ybl');
    });

    test('extracts @paytm UPI IDs', () {
      final p = UpiParser.parseSms(sender: 'XX-BANK', body: 'Payment to shop@paytm of Rs.500');
      expect(p.counterpartyUpiId, 'shop@paytm');
    });

    test('does not extract email-like addresses', () {
      final p = UpiParser.parseSms(sender: 'XX-BANK', body: 'debited Rs.100 contact user@gmail.com');
      expect(p.counterpartyUpiId, isNull);
    });
  });

  // ===========================================================================
  // Counterparty extraction
  // ===========================================================================

  group('Counterparty extraction', () {
    test('SBI debit: trf to NAME', () {
      final p = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 100.00 on date 14Apr26 trf to RAVI KUMAR Refno 123456789012',
      );
      expect(p.counterpartyName, 'RAVI KUMAR');
    });

    test('SBI credit: transfer from NAME', () {
      final p = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI User, your A/c XXXXXX0587-credited by Rs.500.00 on 14-04-26 transfer from ANKIT SHARMA Ref No 123456789012 -SBI',
      );
      expect(p.counterpartyName, 'ANKIT SHARMA');
    });
  });

  // ===========================================================================
  // Dedup — same payment from different sources
  // ===========================================================================

  group('Dedup: same payment from different senders', () {
    test('JD and VA sender produce same bank reference', () {
      final p1 = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969',
      );
      final p2 = UpiParser.parseSms(
        sender: 'VA-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 20.00 on date 12Apr26 trf to MOHAMMAD ZAID Refno 300614399969',
      );
      expect(p1.bankReference, p2.bankReference);
      expect(p1.amount, p2.amount);
      expect(p1.counterpartyName, p2.counterpartyName);
    });
  });

  // ===========================================================================
  // isUpiRelated
  // ===========================================================================

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

    test('detects ₹ symbol', () => expect(UpiParser.isUpiRelated('Sent ₹500'), isTrue));
    test('detects "rs."', () => expect(UpiParser.isUpiRelated('Rs.100 paid'), isTrue));
    test('detects "gpay"', () => expect(UpiParser.isUpiRelated('GPay payment done'), isTrue));
    test('detects "neft"', () => expect(UpiParser.isUpiRelated('NEFT transfer'), isTrue));
    test('detects "imps"', () => expect(UpiParser.isUpiRelated('IMPS txn'), isTrue));
    test('detects "trf to"', () => expect(UpiParser.isUpiRelated('trf to someone'), isTrue));
    test('detects "transfer from"', () => expect(UpiParser.isUpiRelated('transfer from someone'), isTrue));
    test('detects "refno"', () => expect(UpiParser.isUpiRelated('Refno 123'), isTrue));
    test('detects "ref no"', () => expect(UpiParser.isUpiRelated('Ref No 456'), isTrue));

    test('rejects unrelated messages', () {
      expect(UpiParser.isUpiRelated('Your OTP is 123456'), isFalse);
      expect(UpiParser.isUpiRelated('Sale at Flipkart! 50% off'), isFalse);
      expect(UpiParser.isUpiRelated('Your parcel has been shipped'), isFalse);
      expect(UpiParser.isUpiRelated('Appointment reminder tomorrow'), isFalse);
    });
  });

  // ===========================================================================
  // Invalid / non-UPI messages
  // ===========================================================================

  group('Invalid messages', () {
    test('OTP message returns invalid', () {
      final p = UpiParser.parseSms(sender: 'JD-SBIBNK', body: 'Your OTP for transaction is 856432. Do not share.');
      expect(p.isValid, isFalse);
    });

    test('promo message returns invalid', () {
      final p = UpiParser.parseSms(sender: 'BZ-AMAZON', body: 'Big sale on Amazon! Up to 70% off on electronics.');
      expect(p.isValid, isFalse);
    });

    test('empty body returns invalid', () {
      final p = UpiParser.parseSms(sender: 'JD-SBIUPI-S', body: '');
      expect(p.isValid, isFalse);
    });
  });

  // ===========================================================================
  // parseNotification with unknown package
  // ===========================================================================

  group('parseNotification edge cases', () {
    test('unknown package uses "unknown" as app', () {
      final p = UpiParser.parseNotification(
        packageName: 'com.some.random',
        title: 'Payment',
        text: 'Paid ₹100',
      );
      expect(p.upiApp, 'unknown');
    });

    test('combines title and text for parsing', () {
      final p = UpiParser.parseNotification(
        packageName: 'com.google.android.apps.nbu.paisa.user',
        title: 'Received ₹300',
        text: 'from John Doe via UPI Ref No 123456789012',
      );
      expect(p.isValid, isTrue);
      expect(p.amount, 300);
      expect(p.type, TransactionType.credit);
      expect(p.bankReference, '123456789012');
    });
  });

  // ===========================================================================
  // Transaction ID extraction
  // ===========================================================================

  group('Transaction ID extraction', () {
    test('extracts txn id from "txn id: ABC123"', () {
      final p = UpiParser.parseSms(
        sender: 'XX-BANK',
        body: 'Payment successful Rs.100 txn id: TXN456ABC',
      );
      expect(p.upiTransactionId, isNotNull);
    });
  });

  // ===========================================================================
  // Description truncation
  // ===========================================================================

  group('Description handling', () {
    test('short text preserved in full', () {
      final p = UpiParser.parseSms(sender: 'XX-BANK', body: 'Paid Rs.100');
      expect(p.description, 'Paid Rs.100');
    });

    test('text over 200 chars is truncated', () {
      final longBody = 'Paid Rs.100 ${'a' * 250}';
      final p = UpiParser.parseSms(sender: 'XX-BANK', body: longBody);
      expect(p.description!.length, 200);
    });
  });

  // ===========================================================================
  // PhonePe wallet / gift card SMS (JM-/JD-/VA-/AX-PHONPE-S sender IDs)
  // ===========================================================================

  group('PhonePe wallet and gift card SMS', () {
    test('sender "PHONPE" (real-world spelling) maps to phonepe', () {
      expect(UpiParser.identifyAppFromSender('JM-PHONPE-S'), 'phonepe');
      expect(UpiParser.identifyAppFromSender('VA-PHONPE-S'), 'phonepe');
    });

    test('gift card with counterparty and embedded timestamp', () {
      final p = UpiParser.parseSms(
        sender: 'JM-PHONPE-S',
        body:
            "You've paid Rs.207 via PhonePe gift card to SWIGGY on May 29, 2026 at 9:38:00 PM. Not you? Call us on 022-68727374. Remaining balance Rs.1534.",
      );
      expect(p.isValid, isTrue);
      expect(p.amount, 207); // paid amount, NOT the remaining balance
      expect(p.type, TransactionType.debit);
      expect(p.counterpartyName, 'SWIGGY');
      expect(p.balanceAfter, 1534);
      expect(p.embeddedDate, DateTime(2026, 5, 29, 21, 38, 0));
      expect(p.embeddedDateHasTime, isTrue);
      expect(p.upiApp, 'phonepe');
    });

    test('wallet payment with no counterparty, balance with colon + spaces', () {
      final p = UpiParser.parseSms(
        sender: 'JD-PHONPE-S',
        body:
            "You've paid Rs. 1000 via PhonePe wallet. Not you? Call us on 022-68727374. Remaining balance: Rs.  3000. To top-up click https://phone.pe/PHONPE/ws",
      );
      expect(p.isValid, isTrue);
      expect(p.amount, 1000);
      expect(p.type, TransactionType.debit);
      expect(p.balanceAfter, 3000);
      expect(p.embeddedDate, isNull);
    });

    test('gift card to a dotted name is not truncated at the dot', () {
      final p = UpiParser.parseSms(
        sender: 'JM-PHONPE-S',
        body:
            "You've paid Rs.1000 via PhonePe Gift Card to Mr.Shawarma. Not you? Call us on 022-68727374. To buy Gift Card, click https://phone.pe/PHONPE/4fjyavab",
      );
      expect(p.counterpartyName, 'Mr.Shawarma');
      expect(p.amount, 1000);
      expect(p.balanceAfter, isNull);
    });

    test('wallet "for MERCHANT" variant extracts the merchant', () {
      final p = UpiParser.parseSms(
        sender: 'AX-PHONPE-S',
        body:
            "You've paid Rs.100 via PhonePe wallet for Lucky Mens Parlour. Not you? Call us on 022-68727374. Remaining balance: Rs.2187.5. To top-up click https://phone.pe/PHONPE/ws",
      );
      expect(p.counterpartyName, 'Lucky Mens Parlour');
      expect(p.amount, 100);
      expect(p.balanceAfter, 2187.5);
    });

    test('initials with dots survive ("H.A Associates")', () {
      final p = UpiParser.parseSms(
        sender: 'VA-PHONPE-S',
        body:
            "You've paid Rs.85 via PhonePe gift card to H.A Associates on Feb 20, 2026 at 11:02:18 AM. Not you? Call us on 022-68727374. Remaining balance Rs.845.",
      );
      expect(p.counterpartyName, 'H.A Associates');
      expect(p.embeddedDate, DateTime(2026, 2, 20, 11, 2, 18));
    });
  });

  // ===========================================================================
  // Bank refund credits (IT refund, two SBI formats)
  // ===========================================================================

  group('Bank refund credit SMS', () {
    test('"IT Refund ... credited" format parses as credit', () {
      final p = UpiParser.parseSms(
        sender: 'VK-SBIBNK-S',
        body:
            'Dear Customer, For PAN XXXXXX808L, An IT Refund amount of Rs 11640 for AY-2026-27 has been credited to your account XXXXXXX0587 on 2026-07-11. -SBI',
      );
      expect(p.isValid, isTrue);
      expect(p.type, TransactionType.credit);
      expect(p.amount, 11640);
      expect(p.embeddedDate, DateTime(2026, 7, 11));
      expect(p.embeddedDateHasTime, isFalse);
    });

    test('"has credit for ITDTAX REFUND" format parses as credit with balance', () {
      final p = UpiParser.parseSms(
        sender: 'JD-CBSSBI-S',
        body:
            'Your A/C XXXX020587 has credit for ITDTAX REFUND 2026-27 LREPS480 of Rs 11,640.00 on 11/07/26. Avl Bal Rs 79,593.25.-SBI',
      );
      expect(p.isValid, isTrue);
      expect(p.type, TransactionType.credit);
      expect(p.amount, 11640.00);
      expect(p.balanceAfter, 79593.25);
      expect(p.embeddedDate, DateTime(2026, 7, 11));
    });
  });

  // ===========================================================================
  // Balance extraction
  // ===========================================================================

  group('Balance extraction', () {
    test('generic bank tail "Bal INR 23,456.78"', () {
      final p = UpiParser.parseSms(
        sender: 'XX-ICICI',
        body: 'INR 450.00 debited A/c no. XX1234 11-04-26 UPI/P2A/604123456791/ZOMATO. Bal INR 23,456.78.',
      );
      expect(p.amount, 450.00);
      expect(p.balanceAfter, 23456.78);
    });

    test('absent balance stays null', () {
      final p = UpiParser.parseSms(
        sender: 'JD-SBIUPI-S',
        body: 'Dear UPI user A/C X0587 debited by 50.00 on date 11Apr26 trf to RAVI Refno 602560907627',
      );
      expect(p.balanceAfter, isNull);
    });
  });

  // ===========================================================================
  // Embedded date extraction
  // ===========================================================================

  group('Embedded date extraction', () {
    test('SBI debit "on date 12Jul26"', () {
      final p = UpiParser.parseSms(
        sender: 'JK-SBIUPI-S',
        body:
            'Dear UPI user A/C X0587 debited by 15000.00 on date 12Jul26 trf to ROY BROTHERS JEW Refno 619365520493 If not u? call-1800111109-SBI',
      );
      expect(p.embeddedDate, DateTime(2026, 7, 12));
      expect(p.embeddedDateHasTime, isFalse);
    });

    test('SBI credit "on 05-07-26" (dd-mm-yy)', () {
      final p = UpiParser.parseSms(
        sender: 'JK-SBIUPI-S',
        body:
            'Dear UPI User, your A/c XXXXXX0587-credited by Rs.250.00 on 05-07-26 transfer from SUNEETH DEBNATH Ref No 618618940646 -SBI',
      );
      expect(p.embeddedDate, DateTime(2026, 7, 5));
    });

    test('ICICI "on 10-Apr-26" (dd-Mon-yy)', () {
      final p = UpiParser.parseSms(
        sender: 'XX-ICICI',
        body: 'ICICI Bank Acct XX123 debited for Rs 250.00 on 10-Apr-26; UPI:604123456789.',
      );
      expect(p.embeddedDate, DateTime(2026, 4, 10));
    });

    test('12-hour AM/PM conversion: 12:xx AM is midnight, 12:xx PM is noon', () {
      final am = UpiParser.parseSms(
        sender: 'JM-PHONPE-S',
        body: "You've paid Rs.10 via PhonePe gift card to Shop on Jan 5, 2026 at 12:30:00 AM.",
      );
      expect(am.embeddedDate, DateTime(2026, 1, 5, 0, 30, 0));
      final pm = UpiParser.parseSms(
        sender: 'JM-PHONPE-S',
        body: "You've paid Rs.10 via PhonePe gift card to Shop on Jan 5, 2026 at 12:30:00 PM.",
      );
      expect(pm.embeddedDate, DateTime(2026, 1, 5, 12, 30, 0));
    });

    test('no recognizable date stays null', () {
      final p = UpiParser.parseSms(sender: 'XX-BANK', body: 'Paid Rs.100 to Shop');
      expect(p.embeddedDate, isNull);
    });
  });

  // ===========================================================================
  // isUpiRelated — keywords added for refund/wallet/bare credit formats
  // ===========================================================================

  group('isUpiRelated new keywords', () {
    test('detects "credit" without "credited"', () {
      expect(
        UpiParser.isUpiRelated(
            'Your A/C XXXX020587 has credit for ITDTAX REFUND 2026-27 LREPS480 of Rs 11,640.00 on 11/07/26. Avl Bal Rs 79,593.25.-SBI'),
        isTrue,
      );
    });

    test('detects "refund"', () {
      expect(UpiParser.isUpiRelated('An IT Refund amount has been processed'), isTrue);
    });

    test('detects "wallet"', () {
      expect(UpiParser.isUpiRelated("You've paid via PhonePe wallet"), isTrue);
    });
  });
}
