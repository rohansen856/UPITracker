import '../models/transaction_record.dart';

class ParsedUpi {
  final double? amount;
  final TransactionType? type;
  final String? counterpartyName;
  final String? counterpartyUpiId;
  final String? upiTransactionId;
  final String? bankReference;
  final String? accountInfo;
  final String? description;
  final String? upiApp;

  /// Account / wallet balance after the transaction ("Remaining balance
  /// Rs.X", "Avl Bal Rs X"). Used as a dedup discriminator: two otherwise
  /// identical messages with different balances are distinct payments.
  final double? balanceAfter;

  /// Transaction timestamp embedded in the message text ("on May 29, 2026
  /// at 9:38:00 PM", "on date 12Jul26"). More authoritative than the SMS
  /// delivery time, and a dedup discriminator across sender IDs.
  final DateTime? embeddedDate;

  /// Whether [embeddedDate] carries time-of-day precision (vs date only).
  final bool embeddedDateHasTime;

  ParsedUpi({
    this.amount,
    this.type,
    this.counterpartyName,
    this.counterpartyUpiId,
    this.upiTransactionId,
    this.bankReference,
    this.accountInfo,
    this.description,
    this.upiApp,
    this.balanceAfter,
    this.embeddedDate,
    this.embeddedDateHasTime = false,
  });

  bool get isValid => amount != null && amount! > 0 && type != null;

  @override
  String toString() =>
      'ParsedUpi(amount: $amount, type: $type, name: $counterpartyName, '
      'ref: $bankReference, account: $accountInfo, app: $upiApp, '
      'balance: $balanceAfter, embedded: $embeddedDate, valid: $isValid)';
}

class UpiParser {
  // Reference patterns — from broad ("Refno") to specific ("UPI Ref No")
  static final _refPatterns = [
    RegExp(r'Ref\s*(?:No|no|NO)?\.?\s*(\d{10,15})', caseSensitive: false),
    RegExp(r'Refno\s*(\d{10,15})', caseSensitive: false),
    RegExp(r'UPI\s*Ref[:\s.#No]*\s*(\d{10,15})', caseSensitive: false),
  ];

  static final _txnIdPattern = RegExp(
    r'(?:txn\s*(?:id|ID|Id)[:\s]*|Transaction\s*ID[:\s]*)([A-Za-z0-9]+)',
    caseSensitive: false,
  );

  static final _upiIdPattern = RegExp(
    r'([a-zA-Z0-9._-]+@[a-zA-Z]{2,})',
    caseSensitive: false,
  );

  // Account patterns for Indian banks — handles "A/C X0587", "A/c XXXXXX0587", "a/c **1234"
  static final _accountPatterns = [
    RegExp(r'A/[Cc]\s*[Xx]*(\d{4,})', caseSensitive: false),
    RegExp(r'(?:a/c|ac|account)\s*[*Xx]*(\d{4,})', caseSensitive: false),
  ];

  static String? identifyAppFromPackage(String packageName) {
    const mapping = {
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
    return mapping[packageName];
  }

  static String? identifyAppFromSender(String sender) {
    final s = sender.toUpperCase();
    if (s.contains('GPAY') || s.contains('GOOGLE')) return 'gpay';
    if (s.contains('PAYTM')) return 'paytm';
    // Real PhonePe sender IDs spell it "PHONPE" (JM-PHONPE-S, VA-PHONPE-S…).
    if (s.contains('PHONEPE') || s.contains('PHONPE') || s.contains('PHNEPE')) {
      return 'phonepe';
    }
    if (s.contains('BHIM')) return 'bhim';
    if (s.contains('AMAZON')) return 'amazon';
    if (s.contains('SBI')) return 'sbi';
    if (s.contains('HDFC')) return 'hdfc';
    if (s.contains('ICICI')) return 'icici';
    if (s.contains('AXIS')) return 'axis';
    if (s.contains('BOB') || s.contains('BARODA')) return 'bob';
    if (s.contains('PNB')) return 'pnb';
    if (s.contains('KOTAK')) return 'kotak';
    if (s.contains('UNION')) return 'union';
    if (s.contains('CANARA')) return 'canara';
    if (s.contains('INDIAN')) return 'indianbank';
    return null;
  }

  static ParsedUpi parseNotification({
    required String packageName,
    required String title,
    required String text,
  }) {
    final app = identifyAppFromPackage(packageName);
    final combined = '$title $text';
    return _parseText(combined, app ?? 'unknown');
  }

  static ParsedUpi parseSms({
    required String sender,
    required String body,
  }) {
    final app = identifyAppFromSender(sender) ?? 'bank_sms';
    return _parseText(body, app);
  }

  static ParsedUpi _parseText(String text, String app) {
    final type = _detectType(text);
    final amount = _extractAmount(text, type);
    final counterpartyName = _extractCounterparty(text, type);
    final upiId = _extractUpiId(text);
    final ref = _extractRef(text);
    final txnId = _extractTxnId(text);
    final account = _extractAccount(text);
    final balance = _extractBalance(text);
    final embedded = _extractEmbeddedDate(text);

    return ParsedUpi(
      amount: amount,
      type: type,
      counterpartyName: counterpartyName,
      counterpartyUpiId: upiId,
      upiTransactionId: txnId ?? ref,
      bankReference: ref,
      accountInfo: account,
      description: text.length > 200 ? text.substring(0, 200) : text,
      upiApp: app,
      balanceAfter: balance,
      embeddedDate: embedded?.$1,
      embeddedDateHasTime: embedded?.$2 ?? false,
    );
  }

  static TransactionType? _detectType(String text) {
    final t = text.toLowerCase();

    // The explicit settlement verbs describe what happened to the holder's
    // account and outrank the weaker keywords below. When both appear the
    // earlier one wins: "A/c debited and Rs.X added to your UPI Lite" is a
    // debit, "Rs.X credited to a/c ... debited from VPA" is a credit.
    final debitedAt = t.indexOf('debited');
    final creditedAt = t.indexOf('credited');
    if (debitedAt >= 0 && (creditedAt < 0 || debitedAt < creditedAt)) {
      return TransactionType.debit;
    }
    if (creditedAt >= 0) return TransactionType.credit;

    // Check credit first since "credited" is more specific than "credit"
    final creditPatterns = [
      'credited', 'received', 'credit', 'refund', 'cashback',
      'received from', 'money received', 'you received', 'added to',
    ];
    final debitPatterns = [
      'debited', 'paid', 'sent', 'debit', 'transferred',
      'payment of', 'spent', 'charged', 'purchase',
      'you paid', 'you sent', 'payment successful',
      'money sent', 'sent to', 'trf to',
    ];

    for (final kw in creditPatterns) {
      if (t.contains(kw)) return TransactionType.credit;
    }
    for (final kw in debitPatterns) {
      if (t.contains(kw)) return TransactionType.debit;
    }
    return null;
  }

  static double? _extractAmount(String text, TransactionType? type) {
    // Ordered most-specific to least-specific
    final patterns = [
      // "₹500" or "₹ 1,200.50"
      RegExp(r'₹\s*([\d,]+\.?\d{0,2})'),
      // "Rs.20.00" or "Rs 500"
      RegExp(r'Rs\.?\s*([\d,]+\.?\d{0,2})', caseSensitive: false),
      // "INR 500"
      RegExp(r'INR\s*([\d,]+\.?\d{0,2})', caseSensitive: false),
      // SBI-style: "debited by 50.00" or "credited by Rs.20.00" — bare number after by
      RegExp(r'(?:debited|credited)\s+by\s+(?:Rs\.?\s*)?([\d,]+\.?\d{0,2})', caseSensitive: false),
      // "Rupees 500"
      RegExp(r'Rupees\s*([\d,]+\.?\d{0,2})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final raw = match.group(1)!.replaceAll(',', '');
        final value = double.tryParse(raw);
        if (value != null && value > 0) return value;
      }
    }
    return null;
  }

  static String? _extractCounterparty(String text, TransactionType? type) {
    // App/bank-specific patterns first — most precise.
    final sbiPatterns = [
      // SBI debit: "trf to M S SURINDER KUM Refno ..."
      RegExp(r'trf\s+to\s+(.+?)\s+(?:Refno|Ref\s*No|If\s+not)', caseSensitive: false),
      // SBI credit: "transfer from TUMULURI ABHIRAM Ref No ..."
      RegExp(r'transfer\s+from\s+(.+?)\s+(?:Ref\s*No|Refno|-SBI|$)', caseSensitive: false),
      // PhonePe wallet / gift card:
      //   "via PhonePe gift card to SWIGGY on May 29, 2026 at ..."
      //   "via PhonePe Gift Card to Mr.Shawarma. Not you? ..."
      //   "via PhonePe wallet for Lucky Mens Parlour. Not you? ..."
      // Names may contain dots ("Mr.Shawarma", "H.A Associates"), so the
      // terminator is " on <date>" or a period followed by whitespace/end.
      RegExp(r'via\s+PhonePe\s+(?:gift\s*card|wallet)\s+(?:to|for)\s+(.+?)(?:\s+on\s+|\.\s|\.$|$)', caseSensitive: false),
    ];

    for (final pattern in sbiPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        var name = match.group(1)?.trim() ?? '';
        // Clean up trailing garbage
        name = name.replaceAll(RegExp(r'\s+$'), '').trim();
        if (name.isNotEmpty && name.length < 60) return name;
      }
    }

    // Generic patterns
    final genericPatterns = <RegExp>[];

    if (type == TransactionType.debit) {
      genericPatterns.addAll([
        RegExp(r'(?:paid|sent)\s+(?:to\s+)?(?:[₹Rs\.]*[\d,.\s]+\s+)?(?:to\s+)(.+?)(?:\s*\.|\s*$|\s+on\s+|\s+via\s+|\s+UPI)', caseSensitive: false),
        RegExp(r'to\s+([A-Z][a-zA-Z\s]+?)(?:\s*\.|\s*$|\s+on\s+|\s+via\s+|\s+UPI|\s+using)', caseSensitive: false),
      ]);
    } else if (type == TransactionType.credit) {
      genericPatterns.addAll([
        RegExp(r'from\s+([A-Z][a-zA-Z\s]+?)(?:\s*\.|\s*$|\s+on\s+|\s+via\s+|\s+UPI|\s+Ref)', caseSensitive: false),
      ]);
    }

    for (final pattern in genericPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        var name = match.group(1)?.trim() ?? '';
        // Strip any captured currency amount ("₹500", "Rs. 1,200.50") as a
        // token — not as a character class, which would eat the letters
        // R/s from real names ("Rohit" → "ohit").
        name = name
            .replaceAll(RegExp(r'(?:₹|\bRs\.?|\bINR\b)?\s*\d[\d,.]*', caseSensitive: false), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (name.isNotEmpty && name.length < 60) return name;
      }
    }
    return null;
  }

  static String? _extractUpiId(String text) {
    final match = _upiIdPattern.firstMatch(text);
    if (match != null) {
      final id = match.group(1)!;
      // Filter out email-like patterns and common false positives
      if (id.contains('@ok') || id.contains('@ybl') || id.contains('@paytm') ||
          id.contains('@upi') || id.contains('@icici') || id.contains('@sbi') ||
          id.contains('@axl') || id.contains('@ibl') || id.contains('@apl')) {
        return id;
      }
    }
    return null;
  }

  static String? _extractRef(String text) {
    for (final pattern in _refPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(1);
    }
    return null;
  }

  static String? _extractTxnId(String text) {
    final match = _txnIdPattern.firstMatch(text);
    return match?.group(1);
  }

  static String? _extractAccount(String text) {
    for (final pattern in _accountPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return '****${match.group(1)}';
    }
    return null;
  }

  // Balance-after-transaction patterns, most specific first.
  static final _balancePatterns = [
    // PhonePe: "Remaining balance Rs.1534." / "Remaining balance: Rs. 3000."
    RegExp(r'Remaining\s+balance\s*:?\s*(?:Rs\.?|₹|INR)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false),
    // SBI: "Avl Bal Rs 79,593.25"
    RegExp(r'Avl\s+Bal(?:ance)?\s*:?\s*(?:Rs\.?|₹|INR)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false),
    // Generic bank tail: "Bal INR 23,456.78" / "Bal Rs 12350.00"
    RegExp(r'\bBal(?:ance)?\s*:?\s*(?:Rs\.?|₹|INR)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false),
  ];

  static double? _extractBalance(String text) {
    for (final pattern in _balancePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
        if (value != null) return value;
      }
    }
    return null;
  }

  static const _monthNames = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  // Embedded transaction-date patterns. Checked in order; the first match
  // wins. The record tuple is (date, hasTimePrecision).
  static final _embeddedDateWithTime =
      // PhonePe gift card: "on May 29, 2026 at 9:38:00 PM"
      RegExp(r'on\s+([A-Za-z]{3,9})\s+(\d{1,2}),\s*(\d{4})\s+at\s+(\d{1,2}):(\d{2}):(\d{2})\s*(AM|PM)', caseSensitive: false);

  static final _embeddedDateOnlyPatterns = [
    // SBI debit: "on date 12Jul26"
    RegExp(r'on\s+date\s+(\d{1,2})([A-Za-z]{3})(\d{2})\b', caseSensitive: false),
    // ICICI style: "on 10-Apr-26"
    RegExp(r'on\s+(\d{1,2})-([A-Za-z]{3})-(\d{2})\b', caseSensitive: false),
    // ISO: "on 2026-07-11"
    RegExp(r'on\s+(\d{4})-(\d{2})-(\d{2})\b'),
    // SBI credit / HDFC: "on 05-07-26" / "On 11/07/26" (dd-mm-yy)
    RegExp(r'on\s+(\d{1,2})[-/](\d{1,2})[-/](\d{2})\b', caseSensitive: false),
  ];

  static (DateTime, bool)? _extractEmbeddedDate(String text) {
    final withTime = _embeddedDateWithTime.firstMatch(text);
    if (withTime != null) {
      final month = _monthNames[withTime.group(1)!.toLowerCase().substring(0, 3)];
      final day = int.parse(withTime.group(2)!);
      final year = int.parse(withTime.group(3)!);
      var hour = int.parse(withTime.group(4)!);
      final minute = int.parse(withTime.group(5)!);
      final second = int.parse(withTime.group(6)!);
      final pm = withTime.group(7)!.toUpperCase() == 'PM';
      if (month != null && day >= 1 && day <= 31 && hour <= 12) {
        if (pm && hour != 12) hour += 12;
        if (!pm && hour == 12) hour = 0;
        return (DateTime(year, month, day, hour, minute, second), true);
      }
    }

    for (final pattern in _embeddedDateOnlyPatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) continue;
      final int day, year;
      final int? month;
      final g1 = match.group(1)!, g2 = match.group(2)!, g3 = match.group(3)!;
      if (g1.length == 4) {
        // ISO yyyy-mm-dd
        year = int.parse(g1);
        month = int.parse(g2);
        day = int.parse(g3);
      } else if (_monthNames.containsKey(g2.toLowerCase())) {
        // ddMonyy / dd-Mon-yy
        day = int.parse(g1);
        month = _monthNames[g2.toLowerCase()];
        year = 2000 + int.parse(g3);
      } else {
        // dd-mm-yy / dd/mm/yy
        day = int.parse(g1);
        month = int.tryParse(g2);
        year = 2000 + int.parse(g3);
      }
      if (month == null || month < 1 || month > 12) continue;
      if (day < 1 || day > 31) continue;
      return (DateTime(year, month, day), false);
    }
    return null;
  }

  static bool isUpiRelated(String text) {
    final t = text.toLowerCase();
    final keywords = [
      'upi', 'paid', 'received', 'debited', 'credited',
      'payment', 'transaction', '₹', 'rs.', 'inr',
      'gpay', 'phonepe', 'paytm', 'bhim',
      'trf to', 'transfer from', 'refno', 'ref no',
      'neft', 'imps',
      // "has credit for ITDTAX REFUND", "IT Refund ... credited",
      // wallet payments, bare "debit"/"credit" wordings.
      'credit', 'debit', 'refund', 'wallet',
    ];
    return keywords.any((kw) => t.contains(kw));
  }
}
