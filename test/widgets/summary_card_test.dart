import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/widgets/summary_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('SummaryCard', () {
    testWidgets('displays title and formatted amount', (tester) async {
      await tester.pumpWidget(wrap(
        const SummaryCard(
          title: 'Total Spent',
          amount: 1250.75,
          icon: Icons.arrow_upward,
          color: Colors.red,
        ),
      ));

      expect(find.text('Total Spent'), findsOneWidget);
      expect(find.textContaining('1,250.75'), findsOneWidget);
    });

    testWidgets('displays icon', (tester) async {
      await tester.pumpWidget(wrap(
        const SummaryCard(
          title: 'Received',
          amount: 500,
          icon: Icons.arrow_downward,
          color: Colors.green,
        ),
      ));

      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    });

    testWidgets('shows zero amount correctly', (tester) async {
      await tester.pumpWidget(wrap(
        const SummaryCard(
          title: 'Net',
          amount: 0,
          icon: Icons.trending_flat,
          color: Colors.grey,
        ),
      ));

      expect(find.textContaining('₹'), findsOneWidget);
    });
  });
}
