# Spovies Documentation

Architecture and specification documents for the Spovies app.

## Documents

| Document | Description |
|----------|-------------|
| [**TECHNICAL_SPECIFICATION.md**](./TECHNICAL_SPECIFICATION.md) | Full TSD: system vision, architecture, data models, roadmap, Riverpod flow, local-first data strategy |
| [**PLUGIN_SPECIFICATION.md**](./PLUGIN_SPECIFICATION.md) | Plugin manifest and Event Bridge specification (playback is disabled in this build) |
| [**architecture/**](./architecture/README.md) | Design rationale per subsystem: navigation, player, platform policy, ad blocking, plugins, data, layout |

## Quick Links

- **5-Phase Roadmap** → [TECHNICAL_SPECIFICATION.md § 5](./TECHNICAL_SPECIFICATION.md#5-project-roadmap-5-phases)
- **Riverpod Provider Architecture** → [TECHNICAL_SPECIFICATION.md § 6](./TECHNICAL_SPECIFICATION.md#6-state-management-flow--riverpod-structure)
- **Plugin Manifest Schema** → [PLUGIN_SPECIFICATION.md § 2](./PLUGIN_SPECIFICATION.md#2-plugin-manifest)
- **UI/UX Design System** → [TECHNICAL_SPECIFICATION.md § 8](./TECHNICAL_SPECIFICATION.md#8-uiux-design-system)
- **TMDB API Reference** → [TECHNICAL_SPECIFICATION.md § 9](./TECHNICAL_SPECIFICATION.md#9-tmdb-api-integration-reference)

## Design Reference

The visual and interaction quality bar for the app was the original Stitch design mockup (not included in this repository).
Every screen must match or exceed this standard in:

- Glass morphism effects (backdrop-filter blur)
- Cinematic dark theme (`#0A0A0C` bg, `#6C2BEE` primary)
- Typography (Spline Sans)
- Card animations (hover scale, snap scroll)
- Floating glass bottom navigation
