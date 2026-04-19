import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/transaction_provider.dart';
import '../widgets/brand_logo.dart';
import '../widgets/transaction_card.dart';
import '../widgets/filter_sheet.dart';
import 'transaction_detail_screen.dart';

/// The Transactions tab now also hosts the Overview + period picker that used
/// to live on the Analytics screen. Selecting a period applies a date filter
/// both to the list and to the Overview totals so the two stay consistent.
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  /// null = "All time" / current filter set; otherwise the chip window in days.
  int? _selectedDays = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyPeriod(_selectedDays);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Applies the period-chip selection as a date-range filter on the provider,
  /// which updates both the transaction list and the Overview totals.
  void _applyPeriod(int? days) {
    final provider = context.read<TransactionProvider>();
    DateTime? from;
    DateTime? to;
    if (days != null) {
      final now = DateTime.now();
      from = now.subtract(Duration(days: days));
      to = now;
      if (provider.startDate != null && from.isBefore(provider.startDate!)) {
        from = provider.startDate;
      }
    }
    provider.setFilters(
      typeFilter: provider.typeFilter,
      appFilter: provider.appFilter,
      fromDate: from,
      toDate: to,
      searchQuery: provider.searchQuery,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final cs = Theme.of(context).colorScheme;
    final hasFilters = provider.typeFilter != null ||
        provider.appFilter != null ||
        provider.fromDate != null ||
        provider.toDate != null;

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 12, top: 8, bottom: 8),
          child: BrandLogo(size: 32),
        ),
        leadingWidth: 52,
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search transactions...',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (q) => provider.setFilters(
                  searchQuery: q.isEmpty ? null : q,
                  typeFilter: provider.typeFilter,
                  appFilter: provider.appFilter,
                  fromDate: provider.fromDate,
                  toDate: provider.toDate,
                ),
              )
            : const Text('Transactions'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _showSearch = !_showSearch);
              if (!_showSearch) {
                _searchController.clear();
                provider.setFilters(
                  searchQuery: null,
                  typeFilter: provider.typeFilter,
                  appFilter: provider.appFilter,
                  fromDate: provider.fromDate,
                  toDate: provider.toDate,
                );
              }
            },
          ),
          Badge(
            isLabelVisible: hasFilters,
            child: IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: () => _showFilterSheet(context),
            ),
          ),
          if (hasFilters)
            IconButton(
              icon: const Icon(Icons.filter_list_off),
              tooltip: 'Clear filters',
              onPressed: () {
                setState(() => _selectedDays = null);
                provider.clearFilters();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          _PeriodChips(
            selectedDays: _selectedDays,
            onSelected: (days) {
              setState(() => _selectedDays = days);
              _applyPeriod(days);
            },
          ),
          _OverviewCard(
            totalSpent: provider.summary['total_spent'] ?? 0,
            totalReceived: provider.summary['total_received'] ?? 0,
            net: provider.summary['net'] ?? 0,
            periodLabel: _periodLabel(_selectedDays),
          ),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : provider.transactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 56, color: cs.outlineVariant),
                            const SizedBox(height: 12),
                            Text(
                              hasFilters ? 'No matching transactions' : 'No transactions yet',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: provider.transactions.length,
                        itemBuilder: (context, index) {
                          final tx = provider.transactions[index];
                          return TransactionCard(
                            transaction: tx,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TransactionDetailScreen(transactionId: tx.id),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _periodLabel(int? days) {
    if (days == null) return 'All time';
    return switch (days) {
      7 => 'This week',
      30 => 'This month',
      90 => 'Last 3 months',
      365 => 'This year',
      _ => 'Last $days days',
    };
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FilterSheet(),
    );
  }
}

class _PeriodChips extends StatelessWidget {
  final int? selectedDays;
  final ValueChanged<int?> onSelected;
  const _PeriodChips({required this.selectedDays, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final items = const [
      (7, 'Week'),
      (30, 'Month'),
      (90, '3 Months'),
      (365, 'Year'),
    ];
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final (days, label) in items) ...[
            FilterChip(
              selected: selectedDays == days,
              label: Text(label, style: const TextStyle(fontSize: 12)),
              onSelected: (_) => onSelected(days),
            ),
            const SizedBox(width: 8),
          ],
          FilterChip(
            selected: selectedDays == null,
            label: const Text('All', style: TextStyle(fontSize: 12)),
            onSelected: (_) => onSelected(null),
          ),
        ],
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final double totalSpent;
  final double totalReceived;
  final double net;
  final String periodLabel;
  const _OverviewCard({
    required this.totalSpent,
    required this.totalReceived,
    required this.net,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###.##');
    final netPositive = net >= 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: cs.surfaceContainerLow,
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Overview',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(width: 8),
                Text(
                  '· $periodLabel',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _StatRow(
              label: 'Total Spent',
              value: '₹${fmt.format(totalSpent)}',
              color: AppTheme.debitColor,
            ),
            Divider(height: 14, color: cs.outlineVariant.withValues(alpha: 0.4)),
            _StatRow(
              label: 'Total Received',
              value: '₹${fmt.format(totalReceived)}',
              color: AppTheme.creditColor,
            ),
            Divider(height: 14, color: cs.outlineVariant.withValues(alpha: 0.4)),
            _StatRow(
              label: 'Net',
              value: '${netPositive ? '+' : '−'}₹${fmt.format(net.abs())}',
              color: netPositive ? AppTheme.creditColor : AppTheme.debitColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatRow({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(
          value,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}
