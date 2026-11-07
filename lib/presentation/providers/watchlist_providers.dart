import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../data/datasources/local/hive_service.dart';
import '../../data/datasources/local/storage_keys.dart';
import '../../domain/entities/media_item.dart';
import '../../domain/entities/media_metadata.dart';
import '../../domain/entities/media_type.dart';

// ─── Watchlist Notifier ──────────────────────────────────────────────────

class WatchlistNotifier extends Notifier<List<MediaItem>> {
  // Box accessed through HiveService so the box-name constant lives in one
  // place and the central init contract is honoured. A bare
  // `Hive.box('watchlist')` would silently break if HiveService ever renamed
  // or scoped the box.
  Box<Map<dynamic, dynamic>> get _box => HiveService.watchlistBox;

  @override
  List<MediaItem> build() {
    return _loadFromBox();
  }

  List<MediaItem> _loadFromBox() {
    // `_box.values` returns the in-memory cached iterable directly, which
    // is strictly faster than iterating keys and calling get() per item.
    // Entries without an int tmdbId are skipped rather than crashing the
    // provider (and with it Home, Details and the Library) on every launch.
    return [
      for (final data in _box.values)
        if (data['tmdbId'] is int) _fromMap(data),
    ];
  }

  String _keyOf(MediaItem item) =>
      StorageKeys.watchlist(item.type.name, item.tmdbId);

  /// Add a media item to the watchlist.
  void add(MediaItem item) {
    unawaited(_box.put(_keyOf(item), _toMap(item)));
    state = _loadFromBox();
  }

  /// Remove a media item from the watchlist.
  void remove(MediaItem item) {
    unawaited(_box.delete(_keyOf(item)));
    state = _loadFromBox();
  }

  /// Check if a media item is in the watchlist.
  bool contains(MediaItem item) => _box.containsKey(_keyOf(item));

  /// Toggle watchlist membership.
  void toggle(MediaItem item) {
    if (contains(item)) {
      remove(item);
    } else {
      add(item);
    }
  }

  /// Clear all watchlist items. Awaited: Hive empties its in-memory copy
  /// only after the file is truncated, so a title added before that could
  /// otherwise vanish now and reappear on the next launch.
  Future<void> clearAll() async {
    await _box.clear();
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

  /// Tolerant read: a field of the wrong type is treated as missing.
  MediaItem _fromMap(Map<dynamic, dynamic> map) {
    String? text(String k) => map[k] is String ? map[k] as String : null;
    final rating = map['rating'];
    final genreIds = map['genreIds'];
    return MediaItem(
      id: map['tmdbId'].toString(),
      tmdbId: map['tmdbId'] as int,
      type: MediaType.fromString(text('type')),
      title: text('title') ?? '',
      posterPath: text('posterPath'),
      backdropPath: text('backdropPath'),
      overview: text('overview'),
      releaseDate: text('releaseDate'),
      metadata: MediaMetadata(
        rating: rating is num ? rating.toDouble() : null,
        genreIds: genreIds is List ? genreIds.whereType<int>().toList() : [],
      ),
    );
  }
}

// ─── Provider ────────────────────────────────────────────────────────────

final watchlistProvider = NotifierProvider<WatchlistNotifier, List<MediaItem>>(
  WatchlistNotifier.new,
);
