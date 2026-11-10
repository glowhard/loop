import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/pair.dart';
import 'package:loop_app/theme.dart';

void main() {
  testWidgets('the pairing screen asks for the three things the PC shows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: loopTheme(), home: const PairPage(first: true)),
    );
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Port'), findsOneWidget);
    expect(find.text('Pairing code'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Pair'), findsOneWidget);
  });
}
