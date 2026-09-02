import 'package:business_hub_mobile/core/theme/app_colors.dart';
import 'package:business_hub_mobile/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two rules from the UI audit, held in place by tests because both are
/// invisible when they regress: a tap target that shrinks below 48 still
/// looks fine, and an animation that ignores the reduced-motion setting only
/// misbehaves on the devices of the people who asked for it to stop.
Widget _host(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(
      theme: ThemeData(
        extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('AppMotion', () {
    testWidgets('animates when the system has not asked it not to', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(AppMotion.enabled(ctx), isTrue);
      expect(AppMotion.durationOf(ctx, AppMotion.normal), AppMotion.normal);
      expect(AppMotion.offsetOf(ctx, AppMotion.rise), AppMotion.rise);
    });

    testWidgets('collapses to zero when reduced motion is on', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
          disableAnimations: true,
        ),
      );

      expect(AppMotion.enabled(ctx), isFalse);
      expect(AppMotion.durationOf(ctx, AppMotion.slow), Duration.zero);
      // Zero, not a shorter distance — a transform is the thing objected to,
      // so the entrance degrades to a plain fade rather than a fast slide.
      expect(AppMotion.offsetOf(ctx, AppMotion.rise), 0);
    });

    test('nothing is slower than a third of a second', () {
      expect(
        AppMotion.slow.inMilliseconds,
        lessThanOrEqualTo(320),
        reason: 'A till that animates longer than this reads as lag.',
      );
      expect(
        AppMotion.instant < AppMotion.fast &&
            AppMotion.fast < AppMotion.normal &&
            AppMotion.normal < AppMotion.slow,
        isTrue,
      );
    });
  });

  group('Pressable', () {
    testWidgets('shrinks under the finger and springs back on release', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Pressable(
            onTap: () {},
            semanticLabel: 'Add sugar',
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      );

      double scaleNow() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

      expect(scaleNow(), 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Pressable)),
      );
      await tester.pump();
      expect(scaleNow(), AppMotion.pressScale);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleNow(), 1);
    });

    testWidgets('stays still when reduced motion is on', (tester) async {
      await tester.pumpWidget(
        _host(
          Pressable(onTap: () {}, child: const SizedBox(width: 80, height: 80)),
          disableAnimations: true,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(Pressable)),
      );
      await tester.pump();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        1,
        reason: 'Reduced motion removes the transform, not just shortens it.',
      );
      await gesture.up();
    });

    testWidgets('announces itself as a button', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          Pressable(
            onTap: () {},
            semanticLabel: 'Add sugar',
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(Pressable)),
        matchesSemantics(
          label: 'Add sugar',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          // Focusable, and focusable by request — a Bluetooth barcode
          // scanner is a keyboard, and keyboard focus has to land somewhere.
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a non-interactive Pressable is not a button', (tester) async {
      await tester.pumpWidget(
        _host(const Pressable(child: SizedBox(width: 80, height: 80))),
      );

      expect(
        find.descendant(
          of: find.byType(Pressable),
          matching: find.byType(Semantics),
        ),
        findsNothing,
      );
    });
  });

  group('AppListRow', () {
    testWidgets('a title-only row still clears 48', (tester) async {
      await tester.pumpWidget(
        _host(AppListRow(title: 'Day book', onTap: () {})),
      );

      // 12 + 20 + 12 = 44 without the minimum. A thumb misses at 44.
      expect(
        tester.getSize(find.byType(AppListRow)).height,
        greaterThanOrEqualTo(TapTarget.min),
      );
    });

    testWidgets('reads out as one node, title then subtitle', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          AppListRow(
            title: 'Day book',
            subtitle: 'What came in today',
            trailing: const AppTag(label: '3'),
            onTap: () {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(AppListRow)).label,
        'Day book. What came in today',
      );
      handle.dispose();
    });
  });

  group('QuantityStepper', () {
    testWidgets('both step buttons meet the 48 minimum', (tester) async {
      await tester.pumpWidget(
        _host(
          QuantityStepper(quantity: 3, onIncrement: () {}, onDecrement: () {}),
        ),
      );

      for (final icon in <IconData>[Icons.remove_rounded, Icons.add_rounded]) {
        final box = find.ancestor(
          of: find.byIcon(icon),
          matching: find.byType(SizedBox),
        );
        expect(tester.getSize(box.first).height, TapTarget.min);
      }
    });

    testWidgets('each step button is labelled for a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          QuantityStepper(quantity: 3, onIncrement: () {}, onDecrement: () {}),
        ),
      );

      expect(find.bySemanticsLabel('One more'), findsOneWidget);
      expect(find.bySemanticsLabel('One fewer'), findsOneWidget);
      handle.dispose();
    });
  });
}
