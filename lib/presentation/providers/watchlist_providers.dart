import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/datasources/local/hive_service.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_metadata.dart';
import '../../domain/entities/media_type.dart';

// ─── Watchlist Notifier ──────────────────────────────────────────────────

class WatchlistNotifier extends Notifier<List<MediaItem>> {
  // Box accessed through HiveService so the box-name constant lives in one
  // place and the central init contract is honoured. A bare
  // `Hive.box('watchlist')` would silently break if HiveService ever renamed
  // or scoped the box.
  Box<Map> get _box => HiveService.watchlistBox;

  @override
  List<MediaItem> build() {
    return _loadFromBox();
  }

  List<MediaItem> _loadFromBox() {
    // `_box.values` returns the in-memory cached iterable directly, which
    // is strictly faster than iterating keys and calling get() per item.
    return [for (final data in _box.values) _fromMap(data)];
  }

  /// Add a media item to the watchlist.
  void add(MediaItem item) {
    _box.put(item.tmdbId.toString(), _toMap(item));
    state = _loadFromBox();
  }

  /// Remove a media item from the watchlist.
  void remove(int tmdbId) {
    _box.delete(tmdbId.toString());
    state = _loadFromBox();
  }

  /// Check if a media item is in the watchlist.
  bool contains(int tmdbId) {
    return _box.containsKey(tmdbId.toString());
  }

  /// Toggle watchlist membership.
  void toggle(MediaItem item) {
    if (contains(item.tmdbId)) {
      remove(item.tmdbId);
    } else {
      add(item);
    }
  }

  /// Clear all watchlist items.
  void clearAll() {
    _box.clear();
    state = [];
  }

  Map<String, dynamic> _toMap(MediaItem item) => {
    'tmdbId': item.tmdbId,
    'type': item.type.name,
    'title': item.title,
    'posterPath': item.posterPath,
    'backdropPath': item.backdropPath,
    'overview': item.overview,
    'releaseDate': item.releaseDate,
    'rating': item.metadata.rating,
    'genreIds': item.metadata.genreIds.map((id) => id).toList(),
  };

  MediaItem _fromMap(Map<dynamic, dynamic> map) => MediaItem(
    id: map['tmdbId'].toString(),
    tmdbId: map['tmdbId'] as int,
    type: MediaType.fromString(map['type'] as String?),
    title: map['title'] as String? ?? '',
    posterPath: map['posterPath'] as String?,
    backdropPath: map['backdropPath'] as String?,
    overview: map['overview'] as String?,
    releaseDate: map['releaseDate'] as String?,
    metadata: MediaMetadata(
      rating: (map['rating'] as num?)?.toDouble(),
      genreIds:
          (map['genreIds'] as List<dynamic>?)?.map((e) => e as int).toList() ??
          [],
    ),
  );
}

// ─── Provider ────────────────────────────────────────────────────────────

final watchlistProvider = NotifierProvider<WatchlistNotifier, List<MediaItem>>(
  WatchlistNotifier.new,
);
