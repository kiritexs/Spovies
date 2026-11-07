/// Compile-time feature flags.
///
/// `const` so a `false` flag is dead-code-eliminated in release builds.
library;

/// Gates the whole plugin system. When `false` the plugin UI is shown as
/// visibly unavailable and every playback entry point short-circuits with
/// `showPlaybackUnavailableSnack` (`presentation/widgets/app_snack_bar.dart`).
///
/// See `docs/architecture/PLUGINS.md#feature-gating`.
const bool kPluginsEnabled = false;
