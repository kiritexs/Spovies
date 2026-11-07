import 'package:flutter_riverpod/legacy.dart';

/// Currently visible tab in [MainScaffold]'s `IndexedStack`.
///
///   0 = Home, 1 = Discover, 2 = Library, 3 = Settings (see [AppTab])
///
/// Single source of truth for the active tab — nav widgets read and write
/// it, and the system-back handler reads it.
/// See `docs/architecture/NAVIGATION.md`.
final currentTabProvider = StateProvider<int>((_) => 0);
