import 'package:flutter_riverpod/legacy.dart';

/// Currently visible tab in [MainScaffold]'s `IndexedStack`.
///
///   0 = Home, 1 = Explore, 2 = Browse, 3 = Profile
///
/// Single source of truth for the active tab — nav widgets read and write
/// it, and the system-back handler reads it.
/// See `docs/architecture/NAVIGATION.md`.
final currentTabProvider = StateProvider<int>((_) => 0);
