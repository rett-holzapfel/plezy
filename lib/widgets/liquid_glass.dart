import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import '../utils/platform_detector.dart';

/// Name of both the method channel and the platform view type; must match
/// `LiquidGlassPlugin.identifier` on the native side.
const _liquidGlassId = 'com.plezy/liquid_glass';

/// Material of a [LiquidGlass] surface, mirroring `UIGlassEffect.Style`.
enum LiquidGlassStyle {
  /// The standard glass: frosted enough to keep content on it legible over
  /// anything. Use it for bars and controls.
  regular,

  /// Nearly transparent glass for surfaces over rich media, where the content
  /// on top is bold enough to stay legible without the frosting.
  clear,
}

/// Outline of a [LiquidGlass] surface.
@immutable
sealed class LiquidGlassShape {
  const LiquidGlassShape();

  /// Fully rounded ends: a pill, or a circle when square.
  const factory LiquidGlassShape.capsule() = _CapsuleShape;

  /// A rectangle with uniformly rounded corners.
  const factory LiquidGlassShape.rect([double cornerRadius]) = _RectShape;

  Map<String, Object> _encode();
}

final class _CapsuleShape extends LiquidGlassShape {
  const _CapsuleShape();

  @override
  Map<String, Object> _encode() => const {'shape': 'capsule'};

  @override
  bool operator ==(Object other) => other is _CapsuleShape;

  @override
  int get hashCode => (_CapsuleShape).hashCode;
}

final class _RectShape extends LiquidGlassShape {
  const _RectShape([this.cornerRadius = 0]);

  final double cornerRadius;

  @override
  Map<String, Object> _encode() => {'shape': 'rect', 'cornerRadius': cornerRadius};

  @override
  bool operator ==(Object other) => other is _RectShape && other.cornerRadius == cornerRadius;

  @override
  int get hashCode => cornerRadius.hashCode;
}

/// Whether this device renders native Liquid Glass: iOS 26 or later, in a
/// build made with the iOS 26 SDK. False everywhere else, including in tests.
class LiquidGlassSupport {
  LiquidGlassSupport._();

  static const _channel = MethodChannel(_liquidGlassId);

  static final ValueNotifier<bool> available = ValueNotifier(false);
  static bool _started = false;

  static bool get isAvailable => available.value;

  /// Ask the native side once. Fire-and-forget from `main()`: startup awaits
  /// far longer than this round trip before the first glass surface builds,
  /// and [LiquidGlass] listens to [available] in case it ever does not.
  static void ensureInitialized() {
    if (_started) return;
    _started = true;
    if (kIsWeb || !Platform.isIOS || PlatformDetector.isTV()) return;
    unawaited(_query());
  }

  static Future<void> _query() async {
    try {
      available.value = await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      // Older native shell without the plugin.
    } on PlatformException {
      // Leave glass off.
    }
  }

  @visibleForTesting
  static void debugSetAvailable(bool value) => available.value = value;

  /// Runs the native support query regardless of the host platform, so tests
  /// can exercise its handling of the channel's answers and errors.
  @visibleForTesting
  static Future<void> debugQuery() => _query();

  /// Restores the initial state: not yet queried, glass unavailable.
  @visibleForTesting
  static void debugReset() {
    _started = false;
    available.value = false;
  }
}

/// Native iOS Liquid Glass behind [child].
///
/// A `UIGlassEffect` view sits under [child] as a platform view and samples
/// whatever UIKit composites beneath it — the app's own content, or the video
/// layer behind the player — while Flutter draws [child] on top. The glass
/// never takes touches.
///
/// Where native glass is unavailable (see [LiquidGlassSupport]) this builds
/// [fallback] around [child] instead, or [child] alone when there is none,
/// so call sites keep their regular painted look on every other platform.
///
/// Each surface is a platform view, which costs a compositing layer: use it
/// for bars and a handful of controls, not for every item in a list.
///
/// Do not place it under a partially transparent ancestor such as [Opacity]
/// or [FadeTransition]: Flutter applies that opacity as the alpha of the
/// native view, and UIKit renders a visual effect view with an alpha below 1
/// incorrectly. To fade the glass in and out, toggle [visible] instead.
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.shape = const LiquidGlassShape.rect(),
    this.style = LiquidGlassStyle.regular,
    this.tint,
    this.brightness,
    this.visible = true,
    this.fallback,
  });

  final Widget child;
  final LiquidGlassShape shape;
  final LiquidGlassStyle style;

  /// Colors the glass, the way UIKit tints a prominent glass button.
  final Color? tint;

  /// Forces the glass's light or dark appearance. Defaults to the ambient
  /// `Theme.of(context).brightness`, so the glass follows the app's own theme
  /// mode rather than the system's.
  final Brightness? brightness;

  /// Whether the native glass shows. Changes animate natively, with the glass
  /// materializing or dissolving; use this rather than an opacity ancestor.
  /// Affects only the glass: [child] and [fallback] are built either way.
  final bool visible;

  /// The look to use where native glass is unavailable.
  final Widget Function(BuildContext context, Widget child)? fallback;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  /// Id of the live native view, once `onPlatformViewCreated` reported it.
  int? _viewId;

  /// The params the native view currently has, as far as Dart knows.
  Map<String, Object>? _sentParams;

  /// The params for the current widget configuration and ambient theme.
  late Map<String, Object> _params;

  @override
  void initState() {
    super.initState();
    LiquidGlassSupport.available.addListener(_onAvailabilityChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncParams();
  }

  @override
  void didUpdateWidget(LiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncParams();
  }

  @override
  void dispose() {
    LiquidGlassSupport.available.removeListener(_onAvailabilityChanged);
    super.dispose();
  }

  void _syncParams() {
    final brightness = widget.brightness ?? Theme.of(context).brightness;
    _params = {
      ...widget.shape._encode(),
      'style': widget.style.name,
      'brightness': brightness.name,
      'visible': widget.visible,
      if (widget.tint != null) 'tint': widget.tint!.toARGB32(),
    };
    _push();
  }

  void _onAvailabilityChanged() {
    // Either way the platform view is torn down or not yet created; a new one
    // reports itself through `_onPlatformViewCreated`.
    setState(() {
      _viewId = null;
      _sentParams = null;
    });
  }

  void _onPlatformViewCreated(int id, Map<String, Object> creationParams) {
    if (!mounted) return;
    _viewId = id;
    _sentParams = creationParams;
    // Params may have changed between the creation request and now.
    _push();
  }

  /// Restyles the live native view in place when its params are out of date.
  void _push() {
    final id = _viewId;
    final params = _params;
    if (id == null || mapEquals(params, _sentParams)) return;
    _sentParams = params;
    unawaited(
      LiquidGlassSupport._channel.invokeMethod<void>('update', {...params, 'id': id}).catchError((Object error) {
        // Forget the failed params so the next sync sends them again.
        if (identical(_sentParams, params)) _sentParams = null;
        debugPrint('LiquidGlass update failed: $error');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!LiquidGlassSupport.available.value) {
      return widget.fallback?.call(context, widget.child) ?? widget.child;
    }
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: _GlassPlatformView(params: _params, onCreated: _onPlatformViewCreated),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// The platform view, created once with the params current when it mounted.
///
/// It reports those creation params along with the view id, so the parent
/// knows exactly what the native view starts with and sends `update` only
/// for what changed since.
class _GlassPlatformView extends StatefulWidget {
  const _GlassPlatformView({required this.params, required this.onCreated});

  final Map<String, Object> params;
  final void Function(int id, Map<String, Object> creationParams) onCreated;

  @override
  State<_GlassPlatformView> createState() => _GlassPlatformViewState();
}

class _GlassPlatformViewState extends State<_GlassPlatformView> {
  late final Map<String, Object> _creationParams = widget.params;

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: _liquidGlassId,
      creationParams: _creationParams,
      creationParamsCodec: const StandardMessageCodec(),
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      onPlatformViewCreated: (id) => widget.onCreated(id, _creationParams),
    );
  }
}
