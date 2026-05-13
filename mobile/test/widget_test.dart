import 'package:droid_harness_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders Droid Harness shell', (tester) async {
    await tester.pumpWidget(const DroidHarnessApp());
    await tester.pump();

    expect(find.text('Droid Harness'), findsOneWidget);
    expect(find.text('Terminal + IA local no Android'), findsOneWidget);
    expect(find.byIcon(Icons.terminal), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });
}
