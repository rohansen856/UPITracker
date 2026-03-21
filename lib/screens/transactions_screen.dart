import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/transaction_card.dart';
import '../widgets/filter_sheet.dart';
import 'transaction_detail_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
              onPressed: () => provider.clearFilters(),
            ),
        ],
      ),
      body: provider.isLoading
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
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FilterSheet(),
    );
  }
}
