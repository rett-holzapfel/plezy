import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/tabletop_posture.dart';

// iPhone Duo's inner display in landscape.
const _screen = Size(951, 669);

DisplayFeature _feature(
  Rect bounds, {
  DisplayFeatureType type = DisplayFeatureType.fold,
  DisplayFeatureState state = DisplayFeatureState.postureHalfOpened,
}) => DisplayFeature(bounds: bounds, type: type, state: state);

void main() {
  group('tabletopFold', () {
    test('accepts a half-open horizontal fold across the screen', () {
      const fold = Rect.fromLTWH(0, 330, 951, 9);
      expect(tabletopFold(_screen, [_feature(fold)]), fold);
    });

    test('accepts a zero-height fold and a hinge', () {
      const fold = Rect.fromLTWH(0, 334, 951, 0);
      expect(tabletopFold(_screen, [_feature(fold)]), fold);
      expect(tabletopFold(_screen, [_feature(fold, type: DisplayFeatureType.hinge)]), fold);
    });

    test('rejects a vertical fold (book posture)', () {
      expect(tabletopFold(const Size(669, 951), [_feature(const Rect.fromLTWH(330, 0, 9, 951))]), isNull);
    });

    test('rejects a flat or unknown-state fold', () {
      const fold = Rect.fromLTWH(0, 330, 951, 9);
      expect(tabletopFold(_screen, [_feature(fold, state: DisplayFeatureState.postureFlat)]), isNull);
      expect(tabletopFold(_screen, [_feature(fold, state: DisplayFeatureState.unknown)]), isNull);
    });

    test('rejects cutouts and folds too close to an edge', () {
      expect(
        tabletopFold(_screen, [_feature(const Rect.fromLTWH(0, 330, 951, 9), type: DisplayFeatureType.cutout)]),
        isNull,
      );
      expect(tabletopFold(_screen, [_feature(const Rect.fromLTWH(0, 60, 951, 9))]), isNull);
      expect(tabletopFold(_screen, [_feature(const Rect.fromLTWH(0, 600, 951, 9))]), isNull);
    });

    test('rejects a fold that does not span the width', () {
      expect(tabletopFold(_screen, [_feature(const Rect.fromLTWH(0, 330, 400, 9))]), isNull);
    });

  });

  testWidgets('tabletopFoldOf reads MediaQuery', (tester) async {
    const fold = Rect.fromLTWH(0, 330, 951, 9);
    Rect? seen;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: _screen, displayFeatures: [_feature(fold)]),
        child: Builder(
          builder: (context) {
            seen = tabletopFoldOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen, fold);
  });
}
