import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../providers/transaction_provider.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  int _selectedDays = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadForCurrentPeriod();
    });
  }

  void _loadForCurrentPeriod() {
    final provider = context.read<TransactionProvider>();
    final now = DateTime.now();
    var from = now.subtract(Duration(days: _selectedDays));
    if (provider.startDate != null && from.isBefore(provider.startDate!)) {
      from = provider.startDate!;
    }
    provider.loadSummary(from: from, to: now);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionProvider>();
    final cs = Theme.of(context).colorScheme;
    final summary = provider.summary;

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildPeriodChip(7, 'Week'),
                const SizedBox(width: 8),
                _buildPeriodChip(30, 'Month'),
                const SizedBox(width: 8),
                _buildPeriodChip(90, '3 Months'),
                const SizedBox(width: 8),
                _buildPeriodChip(365, 'Year'),
              ],
            ),
            const SizedBox(height: 20),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overview', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    _buildStatRow('Total Spent', summary['total_spent'] ?? 0, AppTheme.debitColor),
                    const Divider(height: 20),
                    _buildStatRow('Total Received', summary['total_received'] ?? 0, AppTheme.creditColor),
                    const Divider(height: 20),
                    _buildStatRow(
                      'Net',
                      (summary['net'] ?? 0).abs(),
                      (summary['net'] ?? 0) >= 0 ? AppTheme.creditColor : AppTheme.debitColor,
                      prefix: (summary['net'] ?? 0) >= 0 ? '+' : '-',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            Text('Daily Trend', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: _DailyChart(days: _selectedDays),
            ),

            if (provider.spendingByApp.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Spending by App', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: _AppPieChart(data: provider.spendingByApp),
              ),
              const SizedBox(height: 12),
              ...provider.spendingByApp.entries.map((e) {
                final total = provider.spendingByApp.values.fold(0.0, (a, b) => a + b);
                final pct = total > 0 ? (e.value / total * 100) : 0;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 6,
                    backgroundColor: _appColor(e.key),
                  ),
                  title: Text(_appLabel(e.key), style: const TextStyle(fontSize: 13)),
                  trailing: Text(
                    '₹${NumberFormat('#,##,###').format(e.value)} (${pct.toStringAsFixed(1)}%)',
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  ),
                );
              }),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodChip(int days, String label) {
    final selected = _selectedDays == days;
    return FilterChip(
      selected: selected,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onSelected: (_) {
        setState(() => _selectedDays = days);
        final provider = context.read<TransactionProvider>();
        final now = DateTime.now();
        var from = now.subtract(Duration(days: days));
        if (provider.startDate != null && from.isBefore(provider.startDate!)) {
          from = provider.startDate!;
        }
        provider.loadSummary(from: from, to: now);
      },
    );
  }

  Widget _buildStatRow(String label, double amount, Color color, {String prefix = ''}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        Text(
          '$prefix₹${NumberFormat('#,##,###.##').format(amount)}',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  String _appLabel(String app) {
    const labels = {
      'gpay': 'Google Pay', 'phonepe': 'PhonePe', 'paytm': 'Paytm',
      'bhim': 'BHIM', 'amazon': 'Amazon Pay', 'bank_sms': 'Bank SMS',
    };
    return labels[app] ?? app;
  }

  Color _appColor(String app) {
    const colors = {
      'gpay': Color(0xFF4285F4), 'phonepe': Color(0xFF5F259F),
      'paytm': Color(0xFF00BAF2), 'bhim': Color(0xFFE8581C),
      'amazon': Color(0xFFFF9900), 'bank_sms': Color(0xFF607D8B),
    };
    return colors[app] ?? Colors.grey;
  }
}

class _DailyChart extends StatelessWidget {
  final int days;
  const _DailyChart({required this.days});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TransactionProvider>();
    final now = DateTime.now();
    var from = now.subtract(Duration(days: days));
    if (provider.startDate != null && from.isBefore(provider.startDate!)) {
      from = provider.startDate!;
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: provider.getDailyTotals(from, now),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Text(
              'No data for this period',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          );
        }

        final data = snapshot.data!;
        final debitByDate = <String, double>{};
        final creditByDate = <String, double>{};

        for (final row in data) {
          final date = row['date'] as String;
          final type = row['transaction_type'] as String;
          final total = (row['total'] as num).toDouble();
          if (type == 'debit') {
            debitByDate[date] = total;
          } else {
            creditByDate[date] = total;
          }
        }

        final allDates = {...debitByDate.keys, ...creditByDate.keys}.toList()..sort();
        if (allDates.isEmpty) {
          return const Center(child: Text('No data'));
        }

        final debitSpots = <FlSpot>[];
        final creditSpots = <FlSpot>[];

        for (int i = 0; i < allDates.length; i++) {
          debitSpots.add(FlSpot(i.toDouble(), debitByDate[allDates[i]] ?? 0));
          creditSpots.add(FlSpot(i.toDouble(), creditByDate[allDates[i]] ?? 0));
        }

        return LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: (allDates.length / 5).ceilToDouble().clamp(1, double.infinity),
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= allDates.length) return const SizedBox();
                    final parts = allDates[idx].split('-');
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${parts[2]}/${parts[1]}',
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 50,
                  getTitlesWidget: (value, meta) {
                    if (value == 0) return const SizedBox();
                    return Text(
                      '₹${NumberFormat.compact().format(value)}',
                      style: const TextStyle(fontSize: 10),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: debitSpots,
                isCurved: true,
                color: AppTheme.debitColor,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppTheme.debitColor.withValues(alpha: 0.08),
                ),
              ),
              LineChartBarData(
                spots: creditSpots,
                isCurved: true,
                color: AppTheme.creditColor,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppTheme.creditColor.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AppPieChart extends StatelessWidget {
  final Map<String, double> data;
  const _AppPieChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.values.fold(0.0, (a, b) => a + b);
    if (total == 0) return const Center(child: Text('No spending data'));

    final colors = {
      'gpay': const Color(0xFF4285F4), 'phonepe': const Color(0xFF5F259F),
      'paytm': const Color(0xFF00BAF2), 'bhim': const Color(0xFFE8581C),
      'amazon': const Color(0xFFFF9900), 'bank_sms': const Color(0xFF607D8B),
    };

    final sections = data.entries.map((e) {
      final pct = e.value / total * 100;
      return PieChartSectionData(
        value: e.value,
        color: colors[e.key] ?? Colors.grey,
        radius: 60,
        title: pct > 5 ? '${pct.toStringAsFixed(0)}%' : '',
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius: 30,
        sectionsSpace: 2,
      ),
    );
  }
}
