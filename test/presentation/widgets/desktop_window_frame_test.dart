// DesktopWindowFrame wraps the tab shell on desktop: it must render, and
// its window buttons must be labelled for screen readers.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spovies/presentation/widgets/desktop_window_frame.dart';

void main() {
  final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  testWidgets('renders labelled window buttons above its child', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopWindowFrame(child: Scaffold(body: Text('shell'))),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('shell'), findsOneWidget);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.bySemanticsLabel('Minimize'), findsOneWidget);
    expect(find.bySemanticsLabel('Maximize'), findsOneWidget);
    semantics.dispose();
  }, skip: !isDesktop);
}
