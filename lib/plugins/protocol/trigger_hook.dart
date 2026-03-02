/// Available trigger hook zones where plugins can appear in the UI.
enum TriggerHook {
  mediaHeader,
  episodeItem,
  mediaCardContext;

  String get value => switch (this) {
    TriggerHook.mediaHeader => 'media_header',
    TriggerHook.episodeItem => 'episode_item',
    TriggerHook.mediaCardContext => 'media_card_context',
  };

  static TriggerHook fromString(String value) => switch (value) {
    'media_header' => TriggerHook.mediaHeader,
    'episode_item' => TriggerHook.episodeItem,
    'media_card_context' => TriggerHook.mediaCardContext,
    _ => TriggerHook.mediaHeader,
  };
}
