import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/transaction_provider.dart';

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  String? _type;
  String? _app;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    final provider = context.read<TransactionProvider>();
    _type = provider.typeFilter;
    _app = provider.appFilter;
    _from = provider.fromDate;
    _to = provider.toDate;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Filter Transactions', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),

          Text('Type', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          SegmentedButton<String?>(
            segments: const [
              ButtonSegment(value: null, label: Text('All')),
              ButtonSegment(value: 'debit', label: Text('Spent')),
              ButtonSegment(value: 'credit', label: Text('Received')),
            ],
            selected: {_type},
            onSelectionChanged: (val) => setState(() => _type = val.first),
          ),

          const SizedBox(height: 16),
          Text('App', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [null, 'gpay', 'phonepe', 'paytm', 'bhim', 'bank_sms', 'other'].map((app) {
              final label = app == null ? 'All' : _appLabel(app);
              return FilterChip(
                selected: _app == app,
                label: Text(label, style: const TextStyle(fontSize: 12)),
                onSelected: (_) => setState(() => _app = app),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),
          Text('Date Range', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _from != null ? DateFormat('dd MMM yy').format(_from!) : 'From',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _from ?? DateTime.now().subtract(const Duration(days: 30)),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) setState(() => _from = date);
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('—'),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _to != null ? DateFormat('dd MMM yy').format(_to!) : 'To',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _to ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) setState(() => _to = date);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Today', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _from = DateTime(now.year, now.month, now.day);
                    _to = now;
                  });
                },
              ),
              ActionChip(
                label: const Text('This Week', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _from = now.subtract(Duration(days: now.weekday - 1));
                    _to = now;
                  });
                },
              ),
              ActionChip(
                label: const Text('This Month', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _from = DateTime(now.year, now.month, 1);
                    _to = now;
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    context.read<TransactionProvider>().clearFilters();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear All'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    context.read<TransactionProvider>().setFilters(
                      typeFilter: _type,
                      appFilter: _app,
                      fromDate: _from,
                      toDate: _to,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _appLabel(String app) {
    const labels = {
      'gpay': 'GPay', 'phonepe': 'PhonePe', 'paytm': 'Paytm',
      'bhim': 'BHIM', 'bank_sms': 'Bank', 'other': 'Other',
    };
    return labels[app] ?? app;
  }
}
