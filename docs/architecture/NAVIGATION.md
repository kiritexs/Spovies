# Navigation & System Back

`lib/presentation/router/app_router.dart`
`lib/presentation/router/main_scaffold.dart`
`lib/presentation/providers/tab_provider.dart`

---

## Structure

```
MaterialApp.router
└── /  →  MainScaffold                  ← PopScope(canPop:false) lives here
│         └── IndexedStack[ Home, Explore, Browse, Profile ]
│             (each wrapped in _KeepAliveTab with a ValueKey)
│
├── /details    ─┐
├── /player     ─┤  parentNavigatorKey: _rootKey
├── /all-media  ─┤  → pushed ABOVE MainScaffold
├── /plugins    ─┤  → the modal route boundary shadows
└── /licenses   ─┘    MainScaffold's PopScope
```

Only one navigator exists — the root. Full-screen routes push onto it via
`parentNavigatorKey: _rootKey`, which overlays `MainScaffold` and hides
its bottom nav automatically.

Tab state lives in `currentTabProvider` (a Riverpod `StateProvider<int>`),
driving `MainScaffold`'s `IndexedStack`. No branch navigators, no
per-branch keys, no back-button dispatcher.

---

## The back-press ladder

A single `PopScope(canPop: false)` at the root of `MainScaffold` catches
every system back while no full-screen route is on top:

1. **Keyboard up + focused field** → unfocus.
2. **Explore tab with active search** → clear the search instead of
   leaving the tab.
3. **Not on Home** → switch to Home, resetting the exit timer so the
   prompt always arms fresh when the user actually lands there.
4. **Home, first press** → arm a 2-second exit prompt (snackbar).
5. **Home, second press within 2 s** → `SystemNavigator.pop()`.

`canPop: false` is what makes it work on Android 13+: it triggers
`setFrameworkHandlesBack(true)` ahead of time, so the OS delivers the
predictive-back gesture to Dart instead of finishing the activity.

When a full-screen route is pushed, its own pop logic runs first —
`MainScaffold`'s `PopScope` sits below it in the modal stack and is
correctly shadowed.

---

## Why `StatefulShellRoute` was abandoned

The original design used `StatefulShellRoute.indexedStack` with four
`StatefulShellBranch`es. Its nested `BackButtonDispatcher` chain calls
`setFrameworkHandlesBack(false)` at the wrong layer, which pre-empts
every back handler placed inside it.

### Approaches tried and discarded

| Approach | Failure |
|---|---|
| Per-tab `PopScope` on each branch | Worked for tabs entered via `goBranch`, but `/home` is the router's initial location and never goes through it — the Home tab either exited the app or fired the wrong tab's handler |
| `goBranch(0)` in `initState` to anchor Home in visit history | `goBranch` is a no-op when `index == currentIndex` |
| Shell-level `WidgetsBindingObserver.didPopRoute` | Never fired |
| Shell-level `PopScope` | Never fired |
| Leaf-level `BackButtonListener` on Home | `BackButtonListener` registers **globally** via `WidgetsBindingObserver`, so with all branches alive in an `IndexedStack` it fired on every tab — showing the Home exit prompt while the user was on Browse |
| `BackButtonListener` + location gate | Still pre-empted |
| Custom `RootBackButtonDispatcher` via `RouterConfig` | Did not fire on Android 13+ predictive back |
| `back_button_interceptor` package | Still broken; also monkey-patches `SystemChannels.navigation.setMethodCallHandler` |

Relevant upstream issues: flutter/flutter
[#143172](https://github.com/flutter/flutter/issues/143172),
[#153672](https://github.com/flutter/flutter/issues/153672),
[#155441](https://github.com/flutter/flutter/issues/155441),
[#170220](https://github.com/flutter/flutter/issues/170220).

### A wiring bug worth remembering

For a while the custom dispatcher *was* correct but never installed:

```dart
MaterialApp.router(
  routerConfig: appRouter,                       // ← this wins
  backButtonDispatcher: spoviesBackButtonDispatcher,  // ← silently ignored
)
```

`MaterialApp.router` only honours the top-level `backButtonDispatcher`
parameter when the individual router parts are passed separately. Given a
unified `routerConfig`, it uses `routerConfig.backButtonDispatcher` — and
`GoRouter` supplies its own default there.

---

## Tab state preservation

`IndexedStack` keeps all four children mounted; only the visible one
paints. `_KeepAliveTab` adds `AutomaticKeepAliveClientMixin` so an
ancestor rebuild cannot dispose a tab's `State`.

Each `_KeepAliveTab` carries an explicit `ValueKey`. Without them,
Flutter's reconciliation could recreate a tab's `State` when an ancestor
rebuilt — which is exactly what happened after every
`/player → /details → back` sequence, because the player's
`SystemChrome` orientation and immersive-UI changes propagate a
`MediaQuery` rebuild down the whole tree.

Together these give the same lifecycle guarantees `StatefulShellBranch`
provided — scroll positions, controllers, and Riverpod sub-tree state
survive a switch — without the back-button coupling.

---

## Full-screen route contract

Every full-screen route is plain: no app-level back override. When
something is pushed, the framework pops it normally and reveals
`MainScaffold` with whichever tab was active.

```
Home → tap movie → /details → back → Home tab
Explore → tap movie → /details → back → Explore tab
Settings → /plugins → back → Settings tab
Home → /details → /player → back → /details → back → Home
```

The player keeps its own `PopScope` to flush window-manager state before
the pop animation — see [PLAYER.md](PLAYER.md#lifecycle-and-teardown).

Routes reached with a wrong or missing `extra` (a deep link, or after
GoRouter state restoration discards extras) render `_RouteErrorScreen`
rather than crashing.

---

## Trade-offs accepted

- **No URL ↔ tab sync.** On tab 2 the URL is `/`, not `/browse`. Fine
  for a single-window app; browser-style address-bar tab tracking would
  need `currentTabProvider` wired back to GoRouter.
- **No per-tab navigation stacks.** `StatefulShellBranch` gave each tab
  its own `Navigator`, so you could be on Home → `/details`, switch to
  Explore, switch back, and still be on `/details`. Full-screen routes
  now push above the whole scaffold. Switching tabs while `/details` is
  open is not a reachable state through the UI.
- **No re-tap-pops-to-root.** `goBranch(initialLocation: …)` gave that
  for free. Moot without per-tab nested navigators; only Settings pushes
  a sub-page (`/plugins`) and that goes above the scaffold.
