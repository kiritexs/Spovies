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

  static ActionType fromString(String value) => switch (value) {
    'webview' => ActionType.webview,
    'externalLink' => ActionType.externalLink,
    'metadataFetch' => ActionType.metadataFetch,
    _ => ActionType.externalLink,
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
