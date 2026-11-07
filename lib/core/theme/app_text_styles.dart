import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Spovies typography system — Spline Sans, matching the original Stitch design mockup (not included in this repository).
abstract final class AppTextStyles {
  /// Bundled in `assets/fonts` (400–700), declared in pubspec.yaml.
  static const String _fontFamily = 'SplineSans';

  // ─── Display ──────────────────────────────────────────────────────────

  /// Hero title — 30px bold.
  static TextStyle get heroTitle => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: Colors.white,
  );

  /// Section headers — 18px bold.
  static TextStyle get sectionTitle => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  /// App name in header — 20px bold.
  static TextStyle get appTitle => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: Colors.white,
  );

  // ─── Body ─────────────────────────────────────────────────────────────

  /// Overview / description text — 14px regular.
  static TextStyle get body => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: Colors.white,
  );

  /// Larger body text — 16px regular.
  static TextStyle get bodyLarge => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: Colors.white,
  );

  // ─── Label ────────────────────────────────────────────────────────────

  /// Button text, nav labels — 14px semibold.
  static TextStyle get label => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  /// Small label — 12px semibold (e.g. "See All", "Welcome back").
  static TextStyle get labelSmall => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  /// Tag/badge text — 12px bold.
  static TextStyle get tag => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  // ─── Caption ──────────────────────────────────────────────────────────

  /// Card title — 14px semibold, truncate.
  static TextStyle get cardTitle => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Colors.white,
  );

  /// Card subtitle (genre, metadata) — 12px regular slate-400.
  static TextStyle get cardSubtitle => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: const Color(0xFF94A3B8),
  );

  /// Metadata row (rating, runtime) — 14px medium slate-300.
  static TextStyle get metadata => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: const Color(0xFFCBD5E1), // Slate 300
  );

  /// Rating badge number — 12px bold white.
  static TextStyle get ratingBadge => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );

  /// Welcome label — xs, semibold, uppercase, wide tracking, brand violet.
  static TextStyle get welcomeLabel => TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 2.0,
    color: AppColors.primaryOnDark,
  );

  // ─── Utility ──────────────────────────────────────────────────────────

  /// Build a full TextTheme for ThemeData.
  static TextTheme get textTheme => TextTheme(
    displayLarge: heroTitle,
    headlineMedium: sectionTitle,
    titleLarge: appTitle,
    bodyMedium: body,
    labelLarge: label,
    labelSmall: cardSubtitle,
  );
}
