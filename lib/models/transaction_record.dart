class TransactionRecord {
  final String id;
  final double amount;
  final TransactionType type;
  final String? upiApp;
  final String? upiTransactionId;
  final String? bankReference;
  final String? counterpartyName;
  final String? counterpartyUpiId;
  final String? accountInfo;
  final String? description;
  String? note;
  String tags;
  final double? latitude;
  final double? longitude;
  final String? locationName;
  final String source;
  final String? rawText;
  final String dedupHash;
  final DateTime transactionDate;
  bool synced;
  final DateTime createdAt;
  DateTime updatedAt;

  TransactionRecord({
    required this.id,
    required this.amount,
    required this.type,
    this.upiApp,
    this.upiTransactionId,
    this.bankReference,
    this.counterpartyName,
    this.counterpartyUpiId,
    this.accountInfo,
    this.description,
    this.note,
    this.tags = '',
    this.latitude,
    this.longitude,
    this.locationName,
    required this.source,
    this.rawText,
    required this.dedupHash,
    required this.transactionDate,
    this.synced = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amount': amount,
      'transaction_type': type.value,
      'upi_app': upiApp,
      'upi_transaction_id': upiTransactionId,
      'bank_reference': bankReference,
      'counterparty_name': counterpartyName,
      'counterparty_upi_id': counterpartyUpiId,
      'account_info': accountInfo,
      'description': description,
      'note': note,
      'tags': tags,
      'latitude': latitude,
      'longitude': longitude,
      'location_name': locationName,
      'source': source,
      'raw_text': rawText,
      'dedup_hash': dedupHash,
      'transaction_date': transactionDate.toIso8601String(),
      'synced': synced ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory TransactionRecord.fromMap(Map<String, dynamic> map) {
    return TransactionRecord(
      id: map['id'] as String,
      amount: (map['amount'] as num).toDouble(),
      type: TransactionType.fromValue(map['transaction_type'] as String),
      upiApp: map['upi_app'] as String?,
      upiTransactionId: map['upi_transaction_id'] as String?,
      bankReference: map['bank_reference'] as String?,
      counterpartyName: map['counterparty_name'] as String?,
      counterpartyUpiId: map['counterparty_upi_id'] as String?,
      accountInfo: map['account_info'] as String?,
      description: map['description'] as String?,
      note: map['note'] as String?,
      tags: (map['tags'] as String?) ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      locationName: map['location_name'] as String?,
      source: map['source'] as String,
      rawText: map['raw_text'] as String?,
      dedupHash: map['dedup_hash'] as String,
      transactionDate: DateTime.parse(map['transaction_date'] as String),
      synced: map['synced'] == 1 || map['synced'] == true,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  TransactionRecord copyWith({
    String? note,
    String? tags,
    bool? synced,
    DateTime? updatedAt,
    String? locationName,
    double? latitude,
    double? longitude,
  }) {
    return TransactionRecord(
      id: id,
      amount: amount,
      type: type,
      upiApp: upiApp,
      upiTransactionId: upiTransactionId,
      bankReference: bankReference,
      counterpartyName: counterpartyName,
      counterpartyUpiId: counterpartyUpiId,
      accountInfo: accountInfo,
      description: description,
      note: note ?? this.note,
      tags: tags ?? this.tags,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      source: source,
      rawText: rawText,
      dedupHash: dedupHash,
      transactionDate: transactionDate,
      synced: synced ?? this.synced,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  List<String> get tagList =>
      tags.isEmpty ? [] : tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();

  String get formattedAmount => '₹${amount.toStringAsFixed(2)}';

  String get upiAppDisplayName {
    switch (upiApp) {
      case 'gpay':
        return 'Google Pay';
      case 'phonepe':
        return 'PhonePe';
      case 'paytm':
        return 'Paytm';
      case 'bhim':
        return 'BHIM';
      case 'whatsapp':
        return 'WhatsApp Pay';
      case 'amazon':
        return 'Amazon Pay';
      case 'mobikwik':
        return 'MobiKwik';
      case 'freecharge':
        return 'Freecharge';
      case 'airtel':
        return 'Airtel Payments';
      case 'jio':
        return 'Jio Pay';
      case 'bank_sms':
        return 'Bank SMS';
      default:
        return upiApp ?? 'Unknown';
    }
  }
}

enum TransactionType {
  debit('debit'),
  credit('credit');

  final String value;
  const TransactionType(this.value);

  factory TransactionType.fromValue(String value) {
    return TransactionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => TransactionType.debit,
    );
  }
}
