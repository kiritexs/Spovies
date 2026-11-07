import 'package:go_router/go_router.dart';

/// Location of the route on top of the stack, e.g. `/details`.
///
/// `routerDelegate.currentConfiguration.uri` is not enough: after
/// `context.push(...)` it still holds the base location (`/`). A pushed
/// route is an `ImperativeRouteMatch` at the end of the match list, and
/// its `matchedLocation` is the pushed path.
String topRouteLocation(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  if (config.isEmpty) return config.uri.path;
  return config.last.matchedLocation;
}
