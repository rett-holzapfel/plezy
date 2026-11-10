import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/widgets/liquid_glass.dart';

const _glassChannel = MethodChannel('com.plezy/liquid_glass');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Decoded creation params of each `create` request on the platform views channel.
  late List<Map<Object?, Object?>> created;

  /// Arguments of each `update` call on the glass channel.
  late List<Map<Object?, Object?>> updates;

  /// Completes the pending `create` request; null when creation is immediate.
  Completer<void>? createGate;

  /// Error the next `update` call answers with, if any.
  PlatformException? nextUpdateError;

  setUp(() {
    created = [];
    updates = [];
    createGate = null;
    nextUpdateError = null;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        final bytes = args['params'] as Uint8List;
        created.add(
          const StandardMessageCodec().decodeMessage(ByteData.sublistView(bytes)) as Map<Object?, Object?>,
        );
        await createGate?.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_glassChannel, (call) async {
      if (call.method == 'update') {
        updates.add(call.arguments as Map<Object?, Object?>);
        final error = nextUpdateError;
        nextUpdateError = null;
        if (error != null) throw error;
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(_glassChannel, null);
    LiquidGlassSupport.debugReset();
  });

  Widget host(
    Widget child, {
    Brightness themeBrightness = Brightness.light,
    Brightness platformBrightness = Brightness.light,
  }) {
    return MediaQuery(
      data: MediaQueryData(platformBrightness: platformBrightness),
      child: Theme(
        data: ThemeData(brightness: themeBrightness),
        child: Directionality(textDirection: TextDirection.ltr, child: child),
      ),
    );
  }

  group('fallback', () {
    testWidgets('builds the fallback around the child when glass is unavailable', (tester) async {
      await tester.pumpWidget(
        host(
          LiquidGlass(
            fallback: (context, child) => ColoredBox(key: const Key('fallback'), color: Colors.black, child: child),
            child: const Text('label'),
          ),
        ),
      );

      expect(find.byKey(const Key('fallback')), findsOneWidget);
      expect(find.text('label'), findsOneWidget);
      expect(find.byType(UiKitView), findsNothing);
      expect(created, isEmpty);
    });

    testWidgets('builds the bare child without a fallback', (tester) async {
      await tester.pumpWidget(host(LiquidGlass(child: const Text('label'))));

      expect(find.text('label'), findsOneWidget);
      expect(find.byType(UiKitView), findsNothing);
    });
  });

  group('creation params', () {
    setUp(() => LiquidGlassSupport.debugSetAvailable(true));

    testWidgets('encode shape, style, tint and visibility', (tester) async {
      await tester.pumpWidget(
        host(
          LiquidGlass(
            shape: const LiquidGlassShape.capsule(),
            style: LiquidGlassStyle.clear,
            tint: const Color(0x80FF0000),
            visible: false,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );

      expect(created, hasLength(1));
      expect(created.single, {
        'shape': 'capsule',
        'style': 'clear',
        'brightness': 'light',
        'visible': false,
        'tint': 0x80FF0000,
      });
    });

    testWidgets('default brightness follows the app theme, not the platform', (tester) async {
      await tester.pumpWidget(
        host(
          LiquidGlass(child: const SizedBox(width: 10, height: 10)),
          themeBrightness: Brightness.dark,
          platformBrightness: Brightness.light,
        ),
      );

      expect(created.single['brightness'], 'dark');
    });

    testWidgets('an explicit brightness wins over the theme', (tester) async {
      await tester.pumpWidget(
        host(
          LiquidGlass(brightness: Brightness.light, child: const SizedBox(width: 10, height: 10)),
          themeBrightness: Brightness.dark,
        ),
      );

      expect(created.single['brightness'], 'light');
    });
  });

  group('update', () {
    setUp(() => LiquidGlassSupport.debugSetAvailable(true));

    testWidgets('creating the view sends no update', (tester) async {
      await tester.pumpWidget(host(LiquidGlass(child: const SizedBox(width: 10, height: 10))));
      await tester.pump();

      expect(created, hasLength(1));
      expect(updates, isEmpty);
    });

    testWidgets('rebuilding with the same config sends no update', (tester) async {
      await tester.pumpWidget(host(LiquidGlass(child: const SizedBox(width: 10, height: 10))));
      await tester.pump();
      await tester.pumpWidget(host(LiquidGlass(child: const SizedBox(width: 10, height: 10))));
      await tester.pump();

      expect(updates, isEmpty);
    });

    testWidgets('a config change restyles the live view once, in place', (tester) async {
      await tester.pumpWidget(host(LiquidGlass(child: const SizedBox(width: 10, height: 10))));
      await tester.pump();
      await tester.pumpWidget(
        host(LiquidGlass(shape: const LiquidGlassShape.rect(12), child: const SizedBox(width: 10, height: 10))),
      );
      await tester.pump();
      await tester.pumpWidget(
        host(LiquidGlass(shape: const LiquidGlassShape.rect(12), child: const SizedBox(width: 10, height: 10))),
      );
      await tester.pump();

      expect(created, hasLength(1));
      expect(updates, hasLength(1));
      expect(updates.single['shape'], 'rect');
      expect(updates.single['cornerRadius'], 12.0);
      expect(updates.single['id'], isA<int>());
    });

    testWidgets('style, tint and visibility changes each send one update', (tester) async {
      await tester.pumpWidget(host(LiquidGlass(child: const SizedBox(width: 10, height: 10))));
      await tester.pump();
      await tester.pumpWidget(
        host(LiquidGlass(style: LiquidGlassStyle.clear, child: const SizedBox(width: 10, height: 10))),
      );
      await tester.pump();
      await tester.pumpWidget(
        host(
          LiquidGlass(
            style: LiquidGlassStyle.clear,
            tint: const Color(0xFF00FF00),
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        host(
          LiquidGlass(
            style: LiquidGlassStyle.clear,
            tint: const Color(0xFF00FF00),
            visible: false,
            child: const SizedBox(width: 10, height: 10),
          ),
        ),
      );
      await tester.pump();

      expect(updates, hasLength(3));
      expect(updates[0]['style'], 'clear');
      expect(updates[1]['tint'], 0xFF00FF00);
      expect(updates[2]['visible'], false);
    });

    testWidgets('a change before the view is created is sent once it exists', (tester) async {
      createGate = Completer<void>();
      await tester.pumpWidget(host(LiquidGlass(child: const SizedBox(width: 10, height: 10))));
      await tester.pumpWidget(
        host(LiquidGlass(style: LiquidGlassStyle.clear, child: const SizedBox(width: 10, height: 10))),
      );
      expect(updates, isEmpty);

      createGate!.complete();
      await tester.pump();

      expect(created, hasLength(1));
      expect(created.single['style'], 'regular');
      expect(updates, hasLength(1));
      expect(updates.single['style'], 'clear');
    });

    testWidgets('a failed update is sent again on the next rebuild', (tester) async {
      await tester.pumpWidget(host(LiquidGlass(child: const SizedBox(width: 10, height: 10))));
      await tester.pump();

      nextUpdateError = PlatformException(code: 'INVALID_ARGS');
      await tester.pumpWidget(
        host(LiquidGlass(style: LiquidGlassStyle.clear, child: const SizedBox(width: 10, height: 10))),
      );
      await tester.pump();
      expect(updates, hasLength(1));

      await tester.pumpWidget(
        host(LiquidGlass(style: LiquidGlassStyle.clear, child: const SizedBox(width: 10, height: 10))),
      );
      await tester.pump();

      expect(updates, hasLength(2));
      expect(updates[1]['style'], 'clear');
    });

    testWidgets('a theme brightness change restyles the live view', (tester) async {
      await tester.pumpWidget(host(LiquidGlass(child: const SizedBox(width: 10, height: 10))));
      await tester.pump();
      await tester.pumpWidget(
        host(LiquidGlass(child: const SizedBox(width: 10, height: 10)), themeBrightness: Brightness.dark),
      );
      await tester.pump();

      expect(updates, hasLength(1));
      expect(updates.single['brightness'], 'dark');
    });
  });

  group('availability', () {
    testWidgets('switches between the fallback and the glass as support changes', (tester) async {
      await tester.pumpWidget(host(LiquidGlass(child: const SizedBox(width: 10, height: 10))));
      expect(find.byType(UiKitView), findsNothing);

      LiquidGlassSupport.debugSetAvailable(true);
      await tester.pump();
      expect(find.byType(UiKitView), findsOneWidget);
      expect(created, hasLength(1));

      LiquidGlassSupport.debugSetAvailable(false);
      await tester.pump();
      expect(find.byType(UiKitView), findsNothing);
    });
  });

  group('LiquidGlassSupport query', () {
    test('marks glass available when the native side supports it', () async {
      messenger.setMockMethodCallHandler(_glassChannel, (call) async => call.method == 'isSupported');

      await LiquidGlassSupport.debugQuery();

      expect(LiquidGlassSupport.isAvailable, isTrue);
    });

    test('leaves glass off when the native side does not support it', () async {
      messenger.setMockMethodCallHandler(_glassChannel, (call) async => false);

      await LiquidGlassSupport.debugQuery();

      expect(LiquidGlassSupport.isAvailable, isFalse);
    });

    test('leaves glass off when the query fails', () async {
      messenger.setMockMethodCallHandler(_glassChannel, (call) async => throw PlatformException(code: 'boom'));

      await LiquidGlassSupport.debugQuery();

      expect(LiquidGlassSupport.isAvailable, isFalse);
    });

    test('leaves glass off when the plugin is missing', () async {
      messenger.setMockMethodCallHandler(_glassChannel, null);

      await LiquidGlassSupport.debugQuery();

      expect(LiquidGlassSupport.isAvailable, isFalse);
    });
  });
}
