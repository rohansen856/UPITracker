import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/transaction_provider.dart';
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
    final recent24h = provider.recent24hTransactions;

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
                    _HeroHeader(
                      spent24h: provider.last24hSummary['total_spent'] ?? 0,
                      received24h: provider.last24hSummary['total_received'] ?? 0,
                      deltaPct: provider.spendingDeltaPct,
                      spark: provider.last7dSpending,
                      txnCount: provider.last24hCount,
                    ),
                    const SizedBox(height: 14),
                    _TotalsRow(
                      totalSpent: provider.summary['total_spent'] ?? 0,
                      totalReceived: provider.summary['total_received'] ?? 0,
                      net: provider.summary['net'] ?? 0,
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Last 24 hours',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          recent24h.isEmpty
                              ? '${provider.totalCount} total'
                              : '${recent24h.length} recent • ${provider.totalCount} total',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            if (recent24h.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: cs.outlineVariant),
                      const SizedBox(height: 16),
                      Text(
                        'No payments in the last 24 hours',
                        style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap Transactions below to see your full history,\nor enable notification & SMS access to auto-capture new payments.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: cs.outline),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final tx = recent24h[index];
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
                  childCount: recent24h.length,
                ),
              ),

            const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
          ],
        ),
      ),
    );
  }
}

/// The top hero card: 24h spending headline, trend badge, and a 7-day sparkline.
class _HeroHeader extends StatelessWidget {
  final double spent24h;
  final double received24h;
  final double? deltaPct;
  final List<double> spark;
  final int txnCount;

  const _HeroHeader({
    required this.spent24h,
    required this.received24h,
    required this.deltaPct,
    required this.spark,
    required this.txnCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inr = NumberFormat('#,##,###.##');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  cs.primary.withValues(alpha: 0.35),
                  cs.primary.withValues(alpha: 0.12),
                ]
              : [
                  cs.primary.withValues(alpha: 0.14),
                  cs.primaryContainer.withValues(alpha: 0.55),
                ],
        ),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Last 24 hours',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              _TrendBadge(deltaPct: deltaPct),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${inr.format(spent24h)}',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.debitColor,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'spent',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.arrow_downward_rounded, size: 14, color: AppTheme.creditColor),
              const SizedBox(width: 2),
              Text(
                '₹${inr.format(received24h)} received',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.creditColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(
                  color: cs.outline,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$txnCount txn${txnCount == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: _Sparkline(values: spark, color: cs.primary),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('7d ago', style: TextStyle(fontSize: 10, color: cs.outline)),
              Text('Today', style: TextStyle(fontSize: 10, color: cs.outline)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  final double? deltaPct;
  const _TrendBadge({required this.deltaPct});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (deltaPct == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          'no prior data',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.outline),
        ),
      );
    }

    final pct = deltaPct!;
    final isUp = pct > 0;
    // Spending UP is "bad" (red); spending DOWN is "good" (green).
    final color = isUp ? AppTheme.debitColor : AppTheme.creditColor;
    final icon = isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    final sign = isUp ? '+' : '';
    final label = pct.abs() < 0.5
        ? 'flat vs yday'
        : '$sign${pct.toStringAsFixed(0)}% vs yday';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Lightweight 7-day bar sparkline. Highlights the tallest (busiest) day.
class _Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  const _Sparkline({required this.values, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (values.isEmpty) {
      return Center(
        child: Text('–', style: TextStyle(color: cs.outline, fontSize: 11)),
      );
    }
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final barSlot = totalWidth / values.length;
        final barWidth = (barSlot * 0.62).clamp(4.0, 16.0);
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Center(
                      child: _Bar(
                        width: barWidth,
                        heightFactor: maxVal == 0 ? 0 : values[i] / maxVal,
                        color: values[i] == maxVal && maxVal > 0
                            ? color
                            : color.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  final double width;
  final double heightFactor;
  final Color color;
  const _Bar({required this.width, required this.heightFactor, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final h = (constraints.maxHeight * heightFactor).clamp(2.0, constraints.maxHeight);
        return Container(
          width: width,
          height: h,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        );
      },
    );
  }
}

/// Compact overall Spent / Received / Net row — shown below the hero card.
class _TotalsRow extends StatelessWidget {
  final double totalSpent;
  final double totalReceived;
  final double net;
  const _TotalsRow({
    required this.totalSpent,
    required this.totalReceived,
    required this.net,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = NumberFormat('#,##,###.##');
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          _TotalsCell(
            label: 'Spent',
            value: '₹${fmt.format(totalSpent)}',
            color: AppTheme.debitColor,
            icon: Icons.arrow_upward_rounded,
          ),
          _VerticalDivider(color: cs.outlineVariant),
          _TotalsCell(
            label: 'Received',
            value: '₹${fmt.format(totalReceived)}',
            color: AppTheme.creditColor,
            icon: Icons.arrow_downward_rounded,
          ),
          _VerticalDivider(color: cs.outlineVariant),
          _TotalsCell(
            label: 'Net',
            value: '₹${fmt.format(net.abs())}',
            color: net >= 0 ? AppTheme.creditColor : AppTheme.debitColor,
            icon: net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          ),
        ],
      ),
    );
  }
}

class _TotalsCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _TotalsCell({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
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
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  final Color color;
  const _VerticalDivider({required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 42, color: color.withValues(alpha: 0.5));
  }
}
