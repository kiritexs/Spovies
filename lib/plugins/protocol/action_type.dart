/// What happens when a plugin action is triggered.
enum ActionType {
  webview,
  externalLink,
  metadataFetch;

  String get value => switch (this) {
    ActionType.webview => 'webview',
    ActionType.externalLink => 'externalLink',
    ActionType.metadataFetch => 'metadataFetch',
  };

  /// Strictly parses [value] against the known set.
  ///
  /// Throws [FormatException] on an unknown string — the previous silent
  /// fallback to [externalLink] meant that a corrupt or malicious plugin
  /// manifest (e.g. one imported from an untrusted `.spovies` backup) could
  /// land on the *most dangerous* sink (`launchUrl(externalApplication)`)
  /// regardless of whether the original value was even a recognised action.
  static ActionType fromString(String value) => switch (value) {
    'webview' => ActionType.webview,
    'externalLink' => ActionType.externalLink,
    'metadataFetch' => ActionType.metadataFetch,
    _ => throw FormatException('Unknown actionType: "$value"'),
  };
}

/// How the WebView is presented.
enum PresentationMode {
  fullscreen,
  popover;

  static PresentationMode fromString(String? value) => switch (value) {
    'popover' => PresentationMode.popover,
    _ => PresentationMode.fullscreen,
  };
}
