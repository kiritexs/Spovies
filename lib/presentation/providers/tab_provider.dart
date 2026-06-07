import 'package:flutter_riverpod/legacy.dart';

/// Currently visible tab in [MainScaffold]'s `IndexedStack`.
///
///   0 = Home
///   1 = Explore
///   2 = Browse (watchlist)
///   3 = Profile (settings)
///
/// This is the single source of truth for the active tab. The bottom-nav
/// and side-nav widgets read it and write to it on tap. The system-back
/// handler in [MainScaffold._onBack] reads it to decide whether to
/// switch to Home or arm the exit prompt. Other widgets that want to
/// programmatically jump to a tab (e.g. Home's search button switching
/// to Explore) write to it directly — no go_router routing involved.
final currentTabProvider = StateProvider<int>((_) => 0);
