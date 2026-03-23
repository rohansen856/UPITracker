import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt/models/transaction_record.dart';
import 'package:receipt/widgets/transaction_card.dart';

void main() {
  final now = DateTime(2026, 4, 13, 14, 30);

  TransactionRecord makeRecord({
    TransactionType type = TransactionType.debit,
    double amount = 500,
    String? counterpartyName = 'John Doe',
    String? upiApp = 'gpay',
    String? note,
    bool synced = false,
  }) {
    return TransactionRecord(
      id: 'test-1', amount: amount, type: type,
      upiApp: upiApp, counterpartyName: counterpartyName,
      source: 'sms', dedupHash: 'hash1',
      transactionDate: now, synced: synced,
      note: note, createdAt: now, updatedAt: now,
    );
  }

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('TransactionCard', () {
    testWidgets('shows counterparty name', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord())));
      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('shows "Unknown" for null counterparty', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(counterpartyName: null))));
      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets('shows debit amount with minus sign', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(type: TransactionType.debit, amount: 250))));
      expect(find.textContaining('-₹'), findsOneWidget);
    });

    testWidgets('shows credit amount with plus sign', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(type: TransactionType.credit, amount: 300))));
      expect(find.textContaining('+₹'), findsOneWidget);
    });

    testWidgets('shows app badge', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(upiApp: 'gpay'))));
      expect(find.text('Google Pay'), findsOneWidget);
    });

    testWidgets('shows note when present', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(note: 'Lunch'))));
      expect(find.text('Lunch'), findsOneWidget);
    });

    testWidgets('hides note when absent', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(note: null))));
      expect(find.text('Lunch'), findsNothing);
    });

    testWidgets('shows cloud-off icon when not synced', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(synced: false))));
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });

    testWidgets('hides cloud-off icon when synced', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(synced: true))));
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    });

    testWidgets('tap callback is invoked', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(TransactionCard(
        transaction: makeRecord(),
        onTap: () => tapped = true,
      )));
      await tester.tap(find.byType(TransactionCard));
      expect(tapped, isTrue);
    });

    testWidgets('shows upward arrow for debit', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(type: TransactionType.debit))));
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    });

    testWidgets('shows downward arrow for credit', (tester) async {
      await tester.pumpWidget(wrap(TransactionCard(transaction: makeRecord(type: TransactionType.credit))));
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    });
  });
}
