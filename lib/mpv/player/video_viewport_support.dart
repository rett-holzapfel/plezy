import 'dart:ui' show Rect;

/// Players that can confine their native video surface to part of the screen
/// while the Flutter UI keeps the rest — the tabletop layout of a foldable,
/// where the picture sits above the fold and the controls below it.
///
/// Kept off [Player] so a backend opts in by implementing it and callers test
/// with `is`; one without it simply keeps the regular full-screen layout.
abstract interface class VideoViewportSupport {
  /// Whether [setVideoViewport] takes effect on this platform and backend.
  bool get supportsVideoViewport;

  /// Show the video inside [viewport] (root logical pixels), letterboxed to
  /// its aspect ratio, or across the whole window again when null.
  Future<void> setVideoViewport(Rect? viewport);
}
