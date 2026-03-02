import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/media_item.dart';
import 'media_providers.dart';

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

/// Debounced search results from TMDB multi-search.
final searchResultsProvider = FutureProvider<List<MediaItem>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().length < 2) return [];

  // Debounce: wait 500ms after last keystroke
  await Future.delayed(const Duration(milliseconds: 500));

  // If the query changed during the delay, cancel this request
  if (ref.read(searchQueryProvider) != query) {
    throw Exception('cancelled');
  }

  final repo = ref.read(mediaRepositoryProvider);
  return repo.search(query.trim());
});
