# Spovies Architecture Notes

Design rationale extracted from inline code comments. Each document
covers one subsystem and answers **why** the code looks the way it does
— failed approaches, platform quirks, and the constraints that shaped
each decision.

The source files keep only short clarifying comments. When you change
behaviour described here, update the matching document.

| Document | Covers |
|---|---|
| [PLAYER.md](PLAYER.md) | WebView player lifecycle, gestures, orientation, hijack recovery, progress tracking |
| [AD_BLOCKING.md](AD_BLOCKING.md) | Injected JS ad/popup defence, remote blocklist sources, what was tried and removed |
| [PLATFORM.md](PLATFORM.md) | Per-platform policy: user agents, content mode, script gating, native vs JS blocking |
| [NAVIGATION.md](NAVIGATION.md) | Router structure, system-back handling, the StatefulShellRoute migration |
| [PLUGINS.md](PLUGINS.md) | Plugin manifests, discovery, URL resolution, the event bridge, feature gating |
| [DATA.md](DATA.md) | Export/import format and its security model |
| [UI_LAYOUT.md](UI_LAYOUT.md) | Responsive grid breakpoints, search state ownership |

## Existing specs

- [../TECHNICAL_SPECIFICATION.md](../TECHNICAL_SPECIFICATION.md)
- [../PLUGIN_SPECIFICATION.md](../PLUGIN_SPECIFICATION.md)
