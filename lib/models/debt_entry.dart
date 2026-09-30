/// A single borrow/lend record tracked in the Debts screen.
///
/// Direction convention:
///  - [DebtDirection.owedToMe] — "this person owes me money".
///  - [DebtDirection.iOwe]     — "I owe this person money".
///
/// Entries stay in the list even after they are marked settled so the user can
/// see history; filter on [settled] to get only outstanding balances.
class DebtEntry {
  final String id;
  final DebtDirection direction;
  final String counterparty;
  final double amount;
  final String? reason;
  final String? note;
  final DateTime createdAt;
  final DateTime? dueDate;
  final bool settled;
  final DateTime? settledAt;
  final DateTime updatedAt;

  DebtEntry({
    required this.id,
    required this.direction,
    required this.counterparty,
    required this.amount,
    this.reason,
    this.note,
    required this.createdAt,
    this.dueDate,
    this.settled = false,
    this.settledAt,
    required this.updatedAt,
  });

  DebtEntry copyWith({
    DebtDirection? direction,
    String? counterparty,
    double? amount,
    String? reason,
    String? note,
    DateTime? dueDate,
    bool? settled,
    DateTime? settledAt,
    DateTime? updatedAt,
    // `settledAt: null` means "keep"; set this to clear it when un-settling.
    bool clearSettledAt = false,
  }) {
    return DebtEntry(
      id: id,
      direction: direction ?? this.direction,
      counterparty: counterparty ?? this.counterparty,
      amount: amount ?? this.amount,
      reason: reason ?? this.reason,
      note: note ?? this.note,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      settled: settled ?? this.settled,
      settledAt: clearSettledAt ? null : (settledAt ?? this.settledAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'direction': direction.value,
      'counterparty': counterparty,
      'amount': amount,
      'reason': reason,
      'note': note,
      'created_at': createdAt.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'settled': settled ? 1 : 0,
      'settled_at': settledAt?.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory DebtEntry.fromMap(Map<String, dynamic> map) {
    return DebtEntry(
      id: map['id'] as String,
      direction: DebtDirection.fromValue(map['direction'] as String),
      counterparty: map['counterparty'] as String,
      amount: (map['amount'] as num).toDouble(),
      reason: map['reason'] as String?,
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      dueDate: (map['due_date'] as String?) == null
          ? null
          : DateTime.parse(map['due_date'] as String),
      settled: (map['settled'] as int? ?? 0) == 1,
      settledAt: (map['settled_at'] as String?) == null
          ? null
          : DateTime.parse(map['settled_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

enum DebtDirection {
  owedToMe('owed_to_me'),
  iOwe('i_owe');

  final String value;
  const DebtDirection(this.value);

  factory DebtDirection.fromValue(String value) {
    return DebtDirection.values.firstWhere(
      (e) => e.value == value,
      orElse: () => DebtDirection.owedToMe,
    );
  }

  String get label => switch (this) {
        DebtDirection.owedToMe => 'Owes me',
        DebtDirection.iOwe => 'I owe',
      };
}
