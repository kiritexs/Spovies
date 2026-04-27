import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/entities/media_item.dart';
import 'media_providers.dart';

// ─── Nav visibility ──────────────────────────────────────────────────────

/// True while the user is actively typing in the search field.
/// ShellScaffold watches this to hide the bottom nav bar.
final isSearchActiveProvider = StateProvider<bool>((ref) => false);

// ─── Clear-search signal ─────────────────────────────────────────────────

/// One-shot signal: the shell increments this when the user presses system
/// back while a search is active. The owner of the search controller (the
/// Discover screen) listens to it and calls its own clear logic.
///
/// Why a signal rather than driving the controller from a provider: the
/// controller's text and selection state are widget-owned and short-lived,
/// while this provider is app-lifetime. Inverting that would force the
/// provider to track ephemeral UI state for no benefit.
class SearchClearSignal extends Notifier<int> {
  @override
  int build() => 0;

  void requestClear() => state++;
}

final searchClearSignalProvider =
    NotifierProvider<SearchClearSignal, int>(SearchClearSignal.new);

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

/// Thrown by [searchResultsProvider] when a newer query supersedes the
/// in-flight one during the debounce window. The UI catches this and shows
/// the shimmer placeholder instead of an error message — string-matching the
/// exception text would silently break if this class moved or its message
/// changed, which is why it's a dedicated type.
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
