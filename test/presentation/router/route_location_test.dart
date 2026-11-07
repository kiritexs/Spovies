import 'dart:async';

// The title bar hides by route, so the top route must be detected after a
// push, not only after a go (pushes leave the match list's uri at '/').

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:spovies/presentation/router/route_location.dart';

void main() {
  testWidgets('reports the pushed route, then the base route after pop', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/details', builder: (_, _) => const Text('details')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(topRouteLocation(router), '/');

    unawaited(router.push('/details'));
    await tester.pumpAndSettle();
    expect(topRouteLocation(router), '/details');

    router.pop();
    await tester.pumpAndSettle();
    expect(topRouteLocation(router), '/');
  });
}
