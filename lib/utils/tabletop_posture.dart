import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Smallest pane, in logical pixels, worth putting content in on either side
/// of the fold. Below it the fold sits too close to an edge to be a tabletop
/// stand (or the reported geometry is transient) and the regular layout wins.
const double _minTabletopPaneExtent = 120;

/// The fold of a device standing half-open like a laptop: iPhone Duo with its
/// hinge partly closed, a book-style Android foldable held sideways, a
/// flip-style phone propped on a table. The fold runs across the whole width,
/// leaving a pane above it to watch and a pane below it to touch.
///
/// Null in every other posture: flat, closed, held like a book (vertical
/// fold), or on a device with no fold. The fold is read from
/// [MediaQueryData.displayFeatures], which Flutter fills on Android and
/// `IphoneDuoScope` fills on iPhone Duo.
Rect? tabletopFoldOf(BuildContext context) =>
    tabletopFold(MediaQuery.sizeOf(context), MediaQuery.displayFeaturesOf(context));

@visibleForTesting
Rect? tabletopFold(Size screen, List<DisplayFeature> features) {
  for (final feature in features) {
    if (feature.type != DisplayFeatureType.fold && feature.type != DisplayFeatureType.hinge) continue;
    if (feature.state != DisplayFeatureState.postureHalfOpened) continue;
    final bounds = feature.bounds;
    // Horizontal and spanning the screen: a vertical fold is the book posture,
    // which keeps the regular full-screen player.
    if (bounds.width <= bounds.height || bounds.width < screen.width * 0.9) continue;
    if (bounds.top < _minTabletopPaneExtent || screen.height - bounds.bottom < _minTabletopPaneExtent) continue;
    return bounds;
  }
  return null;
}
