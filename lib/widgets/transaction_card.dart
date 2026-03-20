import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../models/transaction_record.dart';

class TransactionCard extends StatelessWidget {
  final TransactionRecord transaction;
  final VoidCallback? onTap;

  const TransactionCard({super.key, required this.transaction, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDebit = transaction.type == TransactionType.debit;
    final amountColor = isDebit ? AppTheme.debitColor : AppTheme.creditColor;
    final dateFormat = DateFormat('dd MMM, hh:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: amountColor.withValues(alpha: 0.1),
                child: Icon(
                  isDebit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                  color: amountColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.counterpartyName ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _buildAppBadge(cs),
                        const SizedBox(width: 6),
                        Text(
                          dateFormat.format(transaction.transactionDate),
                          style: TextStyle(fontSize: 11, color: cs.outline),
                        ),
                      ],
                    ),
                    if (transaction.note != null && transaction.note!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        transaction.note!,
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                    '${isDebit ? "-" : "+"}₹${NumberFormat('#,##,###.##').format(transaction.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: amountColor,
                    ),
                  ),
                  if (!transaction.synced)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(Icons.cloud_off_outlined, size: 12, color: cs.outline),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBadge(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        transaction.upiAppDisplayName,
        style: TextStyle(fontSize: 10, color: cs.onSecondaryContainer, fontWeight: FontWeight.w500),
      ),
    );
  }
}
