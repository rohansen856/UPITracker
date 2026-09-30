import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/local_database.dart';
import '../models/debt_entry.dart';

/// Owns the list of borrow/lend entries and exposes the per-person totals
/// consumed by [DebtsScreen].
///
/// We keep this concern separate from [TransactionProvider] because UPI
/// payments and manually-tracked IOUs have very different lifecycles — mixing
/// them would complicate filtering and sync semantics.
class DebtProvider extends ChangeNotifier {
  final LocalDatabase _db = LocalDatabase();
  final _uuid = const Uuid();

  List<DebtEntry> _debts = [];
  bool _isLoading = false;
  String? _error;

  List<DebtEntry> get debts => _debts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Outstanding entries only (not yet settled).
  List<DebtEntry> get outstanding => _debts.where((d) => !d.settled).toList();

  /// Total the user is currently owed by others (unsettled only).
  double get totalOwedToMe => outstanding
      .where((d) => d.direction == DebtDirection.owedToMe)
      .fold(0.0, (a, b) => a + b.amount);

  /// Total the user currently owes to others (unsettled only).
  double get totalIOwe => outstanding
      .where((d) => d.direction == DebtDirection.iOwe)
      .fold(0.0, (a, b) => a + b.amount);

  /// Net position: positive means others owe you more than you owe; negative
  /// means you are a net borrower.
  double get net => totalOwedToMe - totalIOwe;

  /// Group unsettled entries by counterparty and, for each person, produce a
  /// signed net balance (+ve they owe you, -ve you owe them).
  /// Entries are sorted by absolute net balance descending so the biggest
  /// outstanding relationships bubble to the top of the list.
  List<PersonBalance> get peopleBalances {
    final grouped = <String, List<DebtEntry>>{};
    for (final d in outstanding) {
      grouped.putIfAbsent(d.counterparty.trim(), () => []).add(d);
    }
    final people = grouped.entries.map((e) {
      final entries = e.value;
      double signedTotal = 0;
      for (final entry in entries) {
        signedTotal += entry.direction == DebtDirection.owedToMe ? entry.amount : -entry.amount;
      }
      return PersonBalance(
        name: e.key,
        entries: entries..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        netAmount: signedTotal,
      );
    }).toList();
    people.sort((a, b) => b.netAmount.abs().compareTo(a.netAmount.abs()));
    return people;
  }

  /// All entries (settled + outstanding) for a single person, newest first.
  List<DebtEntry> entriesFor(String counterparty) {
    final lower = counterparty.trim().toLowerCase();
    final list = _debts
        .where((d) => d.counterparty.trim().toLowerCase() == lower)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _debts = await _db.getAllDebts();
    } catch (e) {
      _error = 'Failed to load debts: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<DebtEntry> add({
    required DebtDirection direction,
    required String counterparty,
    required double amount,
    String? reason,
    String? note,
    DateTime? dueDate,
  }) async {
    final now = DateTime.now();
    final entry = DebtEntry(
      id: _uuid.v4(),
      direction: direction,
      counterparty: counterparty.trim(),
      amount: amount,
      reason: reason?.trim().isEmpty == true ? null : reason?.trim(),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      createdAt: now,
      dueDate: dueDate,
      updatedAt: now,
    );
    await _db.insertDebt(entry);
    await load();
    return entry;
  }

  Future<void> update(DebtEntry updated) async {
    final withTs = updated.copyWith(updatedAt: DateTime.now());
    await _db.updateDebt(withTs);
    await load();
  }

  Future<void> toggleSettled(String id) async {
    final existing = await _db.getDebtById(id);
    if (existing == null) return;
    final now = DateTime.now();
    final updated = existing.copyWith(
      settled: !existing.settled,
      settledAt: existing.settled ? null : now,
      clearSettledAt: existing.settled,
      updatedAt: now,
    );
    await _db.updateDebt(updated);
    await load();
  }

  Future<void> remove(String id) async {
    await _db.deleteDebt(id);
    await load();
  }
}

/// A grouped view of all outstanding entries with a single person.
class PersonBalance {
  final String name;
  final List<DebtEntry> entries;

  /// +ve = they owe you; −ve = you owe them.
  final double netAmount;

  const PersonBalance({
    required this.name,
    required this.entries,
    required this.netAmount,
  });

  bool get theyOweMe => netAmount > 0;
  bool get iOweThem => netAmount < 0;
  bool get settled => netAmount.abs() < 0.01;
}
