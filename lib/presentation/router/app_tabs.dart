import 'package:flutter/material.dart';

/// The four top-level tabs, in display order (the index is the tab index).
///
/// One source for the mobile nav, the desktop side nav and screen titles,
/// so names and icons can't drift apart again.
enum AppTab {
  home('Home', Icons.home_outlined, Icons.home_rounded),
  discover('Discover', Icons.explore_outlined, Icons.explore_rounded),
  library('Library', Icons.bookmark_border_rounded, Icons.bookmark_rounded),
  settings('Settings', Icons.settings_outlined, Icons.settings_rounded);

  const AppTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
