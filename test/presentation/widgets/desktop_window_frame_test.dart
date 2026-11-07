// DesktopWindowFrame wraps the Navigator from MaterialApp.builder, outside
// any Scaffold. It must render there, and hiding the bar (for the player)
// must not rebuild the Navigator and lose the route stack.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spovies/presentation/widgets/desktop_window_frame.dart';

void main() {
  final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  Widget app(ValueNotifier<bool> show) => MaterialApp(
    builder: (context, child) => ValueListenableBuilder(
      valueListenable: show,
      builder: (context, visible, _) =>
          DesktopWindowFrame(showTitleBar: visible, child: child!),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('pushed route')),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );

  testWidgets('renders window buttons above the Navigator', (tester) async {
    final semantics = tester.ensureSemantics();
    final show = ValueNotifier(true);
    await tester.pumpWidget(app(show));

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.bySemanticsLabel('Minimize'), findsOneWidget);
    semantics.dispose();
  }, skip: !isDesktop);

  testWidgets('hiding the bar keeps the route stack', (tester) async {
    final semantics = tester.ensureSemantics();
    final show = ValueNotifier(true);
    await tester.pumpWidget(app(show));
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('pushed route'), findsOneWidget);

    show.value = false;
    await tester.pumpAndSettle();

    expect(find.text('pushed route'), findsOneWidget);
    expect(find.bySemanticsLabel('Close'), findsNothing);
    semantics.dispose();
  }, skip: !isDesktop);
}
