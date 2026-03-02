import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/media_item.dart';
import 'media_providers.dart';

/// Fetches movie/TV details with all appended data (credits, videos, etc.).
final movieDetailsProvider = FutureProvider.family<MediaItem, int>((
  ref,
  tmdbId,
) async {
  final repo = ref.watch(mediaRepositoryProvider);
  return repo.getMovieDetails(tmdbId);
});
