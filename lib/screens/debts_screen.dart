import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../models/debt_entry.dart';
import '../providers/debt_provider.dart';
import '../widgets/brand_logo.dart';

/// Top-level screen for tracking money the user has lent or borrowed.
///
/// Layout:
///   * Totals header (you're owed / you owe / net).
///   * Tab switcher: All / Owes me / I owe.
///   * Per-person grouped list — tapping a person opens the person's ledger.
///   * FAB to add a new entry.
class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DebtProvider>().load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DebtProvider>();

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 12, top: 8, bottom: 8),
          child: BrandLogo(size: 32),
        ),
        leadingWidth: 52,
        title: const Text('Debts & Lending'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Owes me'),
            Tab(text: 'I owe'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEditSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add entry'),
      ),
      body: RefreshIndicator(
        onRefresh: provider.load,
        child: Column(
          children: [
            _TotalsHeader(
              owedToMe: provider.totalOwedToMe,
              iOwe: provider.totalIOwe,
              net: provider.net,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _PeopleList(filter: null),
                  _PeopleList(filter: DebtDirection.owedToMe),
                  _PeopleList(filter: DebtDirection.iOwe),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddEditSheet(BuildContext context, {DebtEntry? existing}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DebtFormSheet(existing: existing),
    );
  }
}

// ─────────────────────────────── Totals header ──────────────────────────────

class _TotalsHeader extends StatelessWidget {
  final double owedToMe;
  final double iOwe;
  final double net;
  const _TotalsHeader({required this.owedToMe, required this.iOwe, required this.net});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###.##');
    final netPositive = net >= 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary.withValues(alpha: 0.12),
            cs.primaryContainer.withValues(alpha: 0.45),
          ],
        ),
        border: Border.all(color: cs.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            netPositive ? 'You are net owed' : 'You owe net',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${netPositive ? '+' : '−'}₹${fmt.format(net.abs())}',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: netPositive ? AppTheme.creditColor : AppTheme.debitColor,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Owes me',
                  amount: owedToMe,
                  color: AppTheme.creditColor,
                  icon: Icons.arrow_downward_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'I owe',
                  amount: iOwe,
                  color: AppTheme.debitColor,
                  icon: Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;
  const _MiniStat({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###.##');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '₹${fmt.format(amount)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── People list ────────────────────────────────

class _PeopleList extends StatelessWidget {
  /// When non-null, only entries matching this direction are considered when
  /// building the per-person cards.
  final DebtDirection? filter;
  const _PeopleList({required this.filter});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DebtProvider>();
    final cs = Theme.of(context).colorScheme;

    final balances = provider.peopleBalances.where((p) {
      if (filter == null) return true;
      if (filter == DebtDirection.owedToMe) return p.netAmount > 0;
      return p.netAmount < 0;
    }).toList();

    if (provider.isLoading && provider.debts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (balances.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.handshake_outlined, size: 56, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Center(
            child: Text(
              switch (filter) {
                DebtDirection.owedToMe => "Nothing is owed to you",
                DebtDirection.iOwe => "You don't owe anyone",
                _ => 'No debts yet',
              },
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Tap "Add entry" to record a loan or an IOU.',
              style: TextStyle(color: cs.outline, fontSize: 12),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: balances.length,
      itemBuilder: (context, i) => _PersonCard(balance: balances[i]),
    );
  }
}

class _PersonCard extends StatelessWidget {
  final PersonBalance balance;
  const _PersonCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###.##');
    final color = balance.theyOweMe ? AppTheme.creditColor : AppTheme.debitColor;
    final icon = balance.theyOweMe ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
    final sign = balance.theyOweMe ? '+' : '−';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _PersonDetailScreen(name: balance.name),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Text(
                  _initials(balance.name),
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      balance.name.isEmpty ? 'Unknown' : balance.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${balance.entries.length} open entr${balance.entries.length == 1 ? 'y' : 'ies'}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$sign₹${fmt.format(balance.netAmount.abs())}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(icon, size: 11, color: color),
                      const SizedBox(width: 2),
                      Text(
                        balance.theyOweMe ? 'owes you' : 'you owe',
                        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

// ─────────────────────────── Person detail screen ───────────────────────────

class _PersonDetailScreen extends StatelessWidget {
  final String name;
  const _PersonDetailScreen({required this.name});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DebtProvider>();
    final entries = provider.entriesFor(name);
    final cs = Theme.of(context).colorScheme;

    // Re-compute the signed running net so the header keeps working even
    // after entries are settled or removed while this screen is open.
    double net = 0;
    for (final e in entries.where((e) => !e.settled)) {
      net += e.direction == DebtDirection.owedToMe ? e.amount : -e.amount;
    }
    final netPositive = net >= 0;
    final fmt = NumberFormat('#,##,###.##');

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _DebtFormSheet(presetCounterparty: name),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add for this person'),
      ),
      body: entries.isEmpty
          ? Center(
              child: Text('No entries yet', style: TextStyle(color: cs.onSurfaceVariant)),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: (netPositive ? AppTheme.creditColor : AppTheme.debitColor)
                        .withValues(alpha: 0.12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        netPositive ? '$name owes you' : 'You owe $name',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${netPositive ? '+' : '−'}₹${fmt.format(net.abs())}',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: netPositive ? AppTheme.creditColor : AppTheme.debitColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final e in entries) _DebtEntryTile(entry: e),
              ],
            ),
    );
  }
}

class _DebtEntryTile extends StatelessWidget {
  final DebtEntry entry;
  const _DebtEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###.##');
    final dateFmt = DateFormat('dd MMM yyyy');
    final isOwedToMe = entry.direction == DebtDirection.owedToMe;
    final color = isOwedToMe ? AppTheme.creditColor : AppTheme.debitColor;
    final sign = isOwedToMe ? '+' : '−';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: entry.settled ? 0.55 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _DebtFormSheet(existing: entry),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isOwedToMe ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.reason?.isNotEmpty == true
                            ? entry.reason!
                            : (isOwedToMe ? 'Lent to ${entry.counterparty}' : 'Borrowed from ${entry.counterparty}'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          decoration: entry.settled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            dateFmt.format(entry.createdAt),
                            style: TextStyle(fontSize: 11, color: cs.outline),
                          ),
                          if (entry.dueDate != null)
                            Text(
                              '· due ${dateFmt.format(entry.dueDate!)}',
                              style: TextStyle(fontSize: 11, color: cs.outline),
                            ),
                          if (entry.settled && entry.settledAt != null)
                            Text(
                              '· settled ${dateFmt.format(entry.settledAt!)}',
                              style: TextStyle(fontSize: 11, color: AppTheme.creditColor),
                            ),
                        ],
                      ),
                      if (entry.note?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          entry.note!,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$sign₹${fmt.format(entry.amount)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _EntryActions(entry: entry),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryActions extends StatelessWidget {
  final DebtEntry entry;
  const _EntryActions({required this.entry});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<DebtProvider>();
    return PopupMenuButton<String>(
      iconSize: 18,
      padding: EdgeInsets.zero,
      onSelected: (v) async {
        switch (v) {
          case 'toggle':
            await provider.toggleSettled(entry.id);
            break;
          case 'delete':
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete this entry?'),
                content: const Text('This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                ],
              ),
            );
            if (ok == true) await provider.remove(entry.id);
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'toggle',
          child: Text(entry.settled ? 'Mark unsettled' : 'Mark settled'),
        ),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

// ───────────────────────────── Add / edit sheet ────────────────────────────

class _DebtFormSheet extends StatefulWidget {
  final DebtEntry? existing;
  final String? presetCounterparty;
  const _DebtFormSheet({this.existing, this.presetCounterparty});

  @override
  State<_DebtFormSheet> createState() => _DebtFormSheetState();
}

class _DebtFormSheetState extends State<_DebtFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late DebtDirection _direction;
  late final TextEditingController _counterpartyCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _reasonCtrl;
  late final TextEditingController _noteCtrl;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _direction = e?.direction ?? DebtDirection.owedToMe;
    _counterpartyCtrl = TextEditingController(text: e?.counterparty ?? widget.presetCounterparty ?? '');
    _amountCtrl = TextEditingController(text: e == null ? '' : e.amount.toStringAsFixed(2));
    _reasonCtrl = TextEditingController(text: e?.reason ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _dueDate = e?.dueDate;
  }

  @override
  void dispose() {
    _counterpartyCtrl.dispose();
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final editing = widget.existing != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                editing ? 'Edit entry' : 'New debt / loan',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              SegmentedButton<DebtDirection>(
                segments: const [
                  ButtonSegment(
                    value: DebtDirection.owedToMe,
                    icon: Icon(Icons.arrow_downward_rounded),
                    label: Text('They owe me'),
                  ),
                  ButtonSegment(
                    value: DebtDirection.iOwe,
                    icon: Icon(Icons.arrow_upward_rounded),
                    label: Text('I owe'),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => setState(() => _direction = s.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _counterpartyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Person',
                  hintText: 'e.g. Rahul',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final parsed = double.tryParse((v ?? '').trim());
                  if (parsed == null || parsed <= 0) return 'Enter a positive amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'e.g. Dinner, cab share, rent split',
                  prefixIcon: Icon(Icons.edit_note_outlined),
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.sticky_note_2_outlined),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDueDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Due date (optional)',
                    prefixIcon: Icon(Icons.event_outlined),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dueDate == null ? 'Not set' : DateFormat('EEE, dd MMM yyyy').format(_dueDate!),
                          style: TextStyle(
                            color: _dueDate == null ? cs.outline : cs.onSurface,
                          ),
                        ),
                      ),
                      if (_dueDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _dueDate = null),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (editing)
                    TextButton.icon(
                      onPressed: _confirmDelete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: Icon(editing ? Icons.save_rounded : Icons.add_rounded),
                    label: Text(editing ? 'Save' : 'Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<DebtProvider>();
    final amount = double.parse(_amountCtrl.text.trim());
    final counterparty = _counterpartyCtrl.text.trim();
    final reason = _reasonCtrl.text.trim();
    final note = _noteCtrl.text.trim();

    if (widget.existing == null) {
      await provider.add(
        direction: _direction,
        counterparty: counterparty,
        amount: amount,
        reason: reason,
        note: note,
        dueDate: _dueDate,
      );
    } else {
      await provider.update(widget.existing!.copyWith(
        direction: _direction,
        counterparty: counterparty,
        amount: amount,
        reason: reason.isEmpty ? null : reason,
        note: note.isEmpty ? null : note,
        dueDate: _dueDate,
      ));
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<DebtProvider>().remove(widget.existing!.id);
      if (mounted) Navigator.pop(context);
    }
  }
}
