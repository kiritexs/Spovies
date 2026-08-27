import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/media_item.dart';
import 'media_providers.dart';

// ─── Nav visibility ──────────────────────────────────────────────────────

/// True while the user is actively typing in the search field.
/// ShellScaffold watches this to hide the bottom nav bar.
final isSearchActiveProvider = StateProvider<bool>((ref) => false);

// ─── Clear-search signal ─────────────────────────────────────────────────

/// Incremented when system back is pressed with an active search;
/// DiscoverScreen listens and runs its own clear logic. A signal rather
/// than provider-owned controller state — see `docs/architecture/DATA.md`.
class SearchClearSignal extends Notifier<int> {
  @override
  int build() => 0;

  void requestClear() => state++;
}

final searchClearSignalProvider = NotifierProvider<SearchClearSignal, int>(
  SearchClearSignal.new,
);

// ─── Search State ────────────────────────────────────────────────────────

/// The current search query — updated by the search text field.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

/// Thrown when a newer query supersedes the in-flight one during the
/// debounce window. A dedicated type, not a string match — the UI shows
/// the shimmer instead of an error.
class SearchCancelledException implements Exception {
  const SearchCancelledException();

  @override
  String toString() => 'SearchCancelledException: superseded by a newer query';
}

/// Debounced search results from TMDB multi-search.
final searchResultsProvider = FutureProvider<List<MediaItem>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().length < 2) return [];

  // Debounce: wait 500ms after last keystroke
  await Future.delayed(const Duration(milliseconds: 500));

  // If the query changed during the delay, cancel this request.
  if (ref.read(searchQueryProvider) != query) {
    throw const SearchCancelledException();
  }

  final repo = ref.read(mediaRepositoryProvider);
  return repo.search(query.trim());
});
