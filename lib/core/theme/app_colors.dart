import 'package:flutter/material.dart';

/// Spovies color palette — extracted from the original Stitch design mockup (not included in this repository).
///
/// Every color token is mapped 1:1 from the Tailwind config in the HTML template.
abstract final class AppColors {
  // ─── Brand ────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF6C2BEE);
  static const Color primaryMuted = Color(0xE66C2BEE); // 90% opacity

  // ─── Backgrounds ──────────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0A0A0C);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color surfaceDark = Color(0xFF1A1A1E);

  // ─── Glass morphism ───────────────────────────────────────────────────
  static const Color glass = Color(0xB31A1A1E); // rgba(26,26,30,0.70)
  static const Color glassGradientStart = Color(0x991A1A1E); // 0.6 opacity
  static const Color glassGradientEnd = Color(0xD91A1A1E); // 0.85 opacity
  static const Color glassBorder = Color(0x14FFFFFF); // rgba(255,255,255,0.08)

  // ─── Text ─────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
  static const Color textMuted = Color(0xFF64748B); // Slate 500

  // ─── Interactive ──────────────────────────────────────────────────────
  static const Color buttonGlass = Color(0x1AFFFFFF); // white/10
  static const Color buttonGlassBorder = Color(0x33FFFFFF); // white/20
  static const Color buttonGlassHover = Color(0x33FFFFFF); // white/20
  static const Color ratingBadgeBg = Color(0x99000000); // black/60

  // ─── Glow & Shadows ───────────────────────────────────────────────────
  static const Color primaryGlow = Color(0x4D6C2BEE); // rgba(108,43,238,0.3)
  static const Color navShadow = Color(0x80000000); // black/50

  // ─── Misc ─────────────────────────────────────────────────────────────
  static const Color shimmerBase = Color(0xFF1A1A1E);
  static const Color shimmerHighlight = Color(0xFF2A2A30);
  static const Color progressTrack = Color(0x0DFFFFFF); // white/5
  static const Color overlayDark = Color(0x66000000); // black/40
  static const Color dotSeparator = Color(0xFF64748B); // Slate 500

  // ─── Gradients ────────────────────────────────────────────────────────

  /// Hero card bottom → top gradient overlay.
  static const LinearGradient heroOverlay = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xE60A0A0C), // from-background-dark (90%)
      Colors.transparent,
    ],
  );

  /// Header fixed-top gradient fade.
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      backgroundDark,
      Color(0xE60A0A0C), // via background-dark/90
      Colors.transparent,
    ],
    stops: [0.0, 0.6, 1.0],
  );

  /// Glass panel internal gradient.
  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [glassGradientStart, glassGradientEnd],
  );

  // ─── Box Shadows ──────────────────────────────────────────────────────

  /// Primary button glow shadow.
  static final List<BoxShadow> primaryGlowShadow = [
    const BoxShadow(color: primaryGlow, blurRadius: 20, spreadRadius: -5),
  ];

  /// Navigation bar shadow.
  static final List<BoxShadow> navBarShadow = [
    const BoxShadow(
      color: navShadow,
      blurRadius: 40,
      spreadRadius: 0,
      offset: Offset(0, 10),
    ),
  ];
}
