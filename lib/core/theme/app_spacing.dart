import 'package:flutter/material.dart';

/// Spacing and border-radius tokens from stitch/code.html Tailwind config.
abstract final class AppSpacing {
  // ─── Border Radii ─────────────────────────────────────────────────────
  static const double radiusBase = 8.0; // 0.5rem
  static const double radiusLg = 16.0; // 1rem — cards, inputs
  static const double radiusXl = 24.0; // 1.5rem — hero card, bottom nav
  static const double radius2Xl = 32.0; // 2rem — hero poster

  static const BorderRadius borderRadiusBase = BorderRadius.all(
    Radius.circular(radiusBase),
  );
  static const BorderRadius borderRadiusLg = BorderRadius.all(
    Radius.circular(radiusLg),
  );
  static const BorderRadius borderRadiusXl = BorderRadius.all(
    Radius.circular(radiusXl),
  );
  static const BorderRadius borderRadius2Xl = BorderRadius.all(
    Radius.circular(radius2Xl),
  );

  // ─── Spacing ──────────────────────────────────────────────────────────
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;

  // ─── Section-Level ────────────────────────────────────────────────────
  static const double sectionPaddingH = 24.0; // px-6
  static const double sectionGap = 32.0; // mb-8
  static const double cardPadding = 12.0; // p-3
  static const double cardGap = 16.0; // gap-4
  static const double headerPaddingTop = 48.0; // pt-12
  static const double contentPaddingTop = 96.0; // pt-24

  // ─── Component Sizes ──────────────────────────────────────────────────
  static const double mediaCardWidth = 140.0;
  static const double heroAspectRatio = 4 / 5;
  static const double mediaCardAspectRatio = 2 / 3;
  static const double continueWatchingHeight = 96.0;
  static const double continueWatchingThumbWidth = 112.0;
  static const double buttonHeight = 44.0;
  static const double iconButtonSize = 44.0;
  static const double searchButtonSize = 40.0;
  static const double ratingBadgeSize = 32.0;
  static const double progressBarHeight = 4.0;
  static const double navBarBottom = 24.0;
  static const double navBarHorizontal = 24.0;

  // ─── Icon Sizes ───────────────────────────────────────────────────────
  static const double iconSm = 16.0;
  static const double iconMd = 20.0;
  static const double iconLg = 24.0;

  // ─── Edge Insets ──────────────────────────────────────────────────────
  static const EdgeInsets sectionPadding = EdgeInsets.symmetric(
    horizontal: sectionPaddingH,
  );
  static const EdgeInsets cardContentPadding = EdgeInsets.all(cardPadding);
}
