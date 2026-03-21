import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../models/transaction_record.dart';
import '../providers/transaction_provider.dart';

class TransactionDetailScreen extends StatefulWidget {
  final String transactionId;

  const TransactionDetailScreen({super.key, required this.transactionId});

  @override
  State<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  late TextEditingController _noteController;
  late TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _tagsController = TextEditingController();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  TransactionRecord? _findTransaction(TransactionProvider provider) {
    try {
      return provider.transactions.firstWhere((t) => t.id == widget.transactionId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final tx = _findTransaction(provider);
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('EEEE, dd MMM yyyy • hh:mm a');

    if (tx == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Transaction not found')),
      );
    }

    if (_noteController.text.isEmpty && tx.note != null) {
      _noteController.text = tx.note!;
    }
    if (_tagsController.text.isEmpty && tx.tags.isNotEmpty) {
      _tagsController.text = tx.tags;
    }

    final isDebit = tx.type == TransactionType.debit;
    final amountColor = isDebit ? AppTheme.debitColor : AppTheme.creditColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, provider, tx),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: amountColor.withValues(alpha: 0.12),
                    child: Icon(
                      isDebit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: amountColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${isDebit ? "- " : "+ "}₹${NumberFormat('#,##,###.##').format(tx.amount)}',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isDebit ? 'PAID' : 'RECEIVED',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: amountColor.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dateFormat.format(tx.transactionDate),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            _buildInfoRow(context, 'Counterparty', tx.counterpartyName ?? 'Unknown'),
            if (tx.counterpartyUpiId != null)
              _buildInfoRow(context, 'UPI ID', tx.counterpartyUpiId!),
            _buildInfoRow(context, 'App', tx.upiAppDisplayName),
            _buildInfoRow(context, 'Source', tx.source.toUpperCase()),
            if (tx.upiTransactionId != null)
              _buildInfoRow(context, 'Transaction ID', tx.upiTransactionId!),
            if (tx.bankReference != null)
              _buildInfoRow(context, 'Bank Reference', tx.bankReference!),
            if (tx.accountInfo != null)
              _buildInfoRow(context, 'Account', tx.accountInfo!),
            _buildInfoRow(context, 'Synced', tx.synced ? 'Yes' : 'Pending'),

            if (tx.locationName != null) ...[
              const SizedBox(height: 4),
              _buildInfoRow(context, 'Location', tx.locationName!),
            ],

            const SizedBox(height: 24),
            Text('Note', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(hintText: 'Add a note...'),
              maxLines: 3,
              onChanged: (_) => _saveNote(provider, tx),
            ),

            const SizedBox(height: 16),
            Text('Tags', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Comma-separated (e.g. food, travel, rent)',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tagsController,
              decoration: const InputDecoration(hintText: 'Add tags...'),
              onChanged: (_) => _saveTags(provider, tx),
            ),

            if (tx.tagList.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tx.tagList.map((tag) {
                  return Chip(
                    label: Text(tag, style: const TextStyle(fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      final tags = tx.tagList.where((t) => t != tag).join(', ');
                      _tagsController.text = tags;
                      provider.updateTags(tx.id, tags);
                    },
                  );
                }).toList(),
              ),
            ],

            if (tx.rawText != null && tx.rawText!.isNotEmpty) ...[
              const SizedBox(height: 24),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Original Message', style: Theme.of(context).textTheme.titleSmall),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(tx.rawText!, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _saveNote(TransactionProvider provider, TransactionRecord tx) {
    Future.delayed(const Duration(milliseconds: 500), () {
      provider.updateNote(tx.id, _noteController.text);
    });
  }

  void _saveTags(TransactionProvider provider, TransactionRecord tx) {
    Future.delayed(const Duration(milliseconds: 500), () {
      provider.updateTags(tx.id, _tagsController.text);
    });
  }

  void _confirmDelete(BuildContext context, TransactionProvider provider, TransactionRecord tx) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: Text('Delete this ${tx.formattedAmount} transaction?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              provider.deleteTransaction(tx.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
