import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/transaction_provider.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_card.dart';
import 'transaction_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _syncSpinController;

  @override
  void initState() {
    super.initState();
    _syncSpinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _syncSpinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final cs = Theme.of(context).colorScheme;
    final recent = provider.transactions.take(10).toList();

    if (provider.isSyncing) {
      _syncSpinController.repeat();
    } else {
      _syncSpinController.stop();
      _syncSpinController.reset();
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await provider.loadTransactions();
          await provider.loadSummary();
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              title: const Text('UPI Tracker'),
              pinned: true,
              actions: [
                if (provider.isListening)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.creditColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.sensors, size: 14, color: AppTheme.creditColor),
                        const SizedBox(width: 4),
                        Text('Live', style: TextStyle(fontSize: 12, color: AppTheme.creditColor, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                IconButton(
                  icon: RotationTransition(
                    turns: _syncSpinController,
                    child: const Icon(Icons.sync),
                  ),
                  onPressed: provider.isSyncing
                      ? null
                      : () async {
                          final result = await provider.triggerSync();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(result.message)),
                            );
                          }
                        },
                ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SummaryCard(
                            title: 'Total Spent',
                            amount: provider.summary['total_spent'] ?? 0,
                            icon: Icons.arrow_upward_rounded,
                            color: AppTheme.debitColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SummaryCard(
                            title: 'Received',
                            amount: provider.summary['total_received'] ?? 0,
                            icon: Icons.arrow_downward_rounded,
                            color: AppTheme.creditColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: (provider.summary['net'] ?? 0) >= 0
                              ? AppTheme.creditColor.withValues(alpha: 0.15)
                              : AppTheme.debitColor.withValues(alpha: 0.15),
                          child: Icon(
                            (provider.summary['net'] ?? 0) >= 0
                                ? Icons.trending_up_rounded
                                : Icons.trending_down_rounded,
                            color: (provider.summary['net'] ?? 0) >= 0
                                ? AppTheme.creditColor
                                : AppTheme.debitColor,
                          ),
                        ),
                        title: const Text('Net Balance', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        trailing: Text(
                          '₹${NumberFormat('#,##,###.##').format((provider.summary['net'] ?? 0).abs())}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: (provider.summary['net'] ?? 0) >= 0
                                ? AppTheme.creditColor
                                : AppTheme.debitColor,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.today_rounded, size: 18, color: cs.primary),
                          const SizedBox(width: 10),
                          Text('Today', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
                          const Spacer(),
                          Text(
                            '₹${NumberFormat('#,##,###.##').format(provider.todaySummary['total_spent'] ?? 0)}',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.debitColor),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('/', style: TextStyle(color: cs.outline, fontSize: 14)),
                          ),
                          Text(
                            '₹${NumberFormat('#,##,###.##').format(provider.todaySummary['total_received'] ?? 0)}',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.creditColor),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Transactions', style: Theme.of(context).textTheme.titleSmall),
                        Text('${provider.totalCount} total', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            if (recent.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: cs.outlineVariant),
                      const SizedBox(height: 16),
                      Text(
                        'No transactions yet',
                        style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enable notification access and SMS permissions\nto start tracking your UPI payments',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: cs.outline),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final tx = recent[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TransactionCard(
                        transaction: tx,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TransactionDetailScreen(transactionId: tx.id),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: recent.length,
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
    );
  }

}
