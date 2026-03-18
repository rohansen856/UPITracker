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
  });

  bool get isValid => amount != null && amount! > 0 && type != null;

  @override
  String toString() =>
      'ParsedUpi(amount: $amount, type: $type, name: $counterpartyName, '
      'ref: $bankReference, account: $accountInfo, app: $upiApp, valid: $isValid)';
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
    if (s.contains('PHONEPE') || s.contains('PHNEPE')) return 'phonepe';
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
    );
  }

  static TransactionType? _detectType(String text) {
    final t = text.toLowerCase();

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
    // SBI-specific patterns first (most common for this user)
    final sbiPatterns = [
      // SBI debit: "trf to M S SURINDER KUM Refno ..."
      RegExp(r'trf\s+to\s+(.+?)\s+(?:Refno|Ref\s*No|If\s+not)', caseSensitive: false),
      // SBI credit: "transfer from TUMULURI ABHIRAM Ref No ..."
      RegExp(r'transfer\s+from\s+(.+?)\s+(?:Ref\s*No|Refno|-SBI|$)', caseSensitive: false),
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
        name = name.replaceAll(RegExp(r'[₹Rs\.\d,]+'), '').trim();
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

  static bool isUpiRelated(String text) {
    final t = text.toLowerCase();
    final keywords = [
      'upi', 'paid', 'received', 'debited', 'credited',
      'payment', 'transaction', '₹', 'rs.', 'inr',
      'gpay', 'phonepe', 'paytm', 'bhim',
      'trf to', 'transfer from', 'refno', 'ref no',
      'neft', 'imps',
    ];
    return keywords.any((kw) => t.contains(kw));
  }
}
