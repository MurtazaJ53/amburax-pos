import 'dart:async';

import 'package:business_hub_mobile/core/theme/app_colors.dart';
import 'package:business_hub_mobile/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The behaviour worth protecting here is the async state. The 199
/// hand-rolled busy flags this widget replaces mostly got the happy path
/// right; what they got wrong was the throw, which leaves the button
/// disabled forever with nothing on screen explaining why.
Widget _host(Widget child) {
  return MaterialApp(
    theme: ThemeData(
      extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('AppButton async state', () {
    testWidgets('disables and spins while the future is in flight', (
      tester,
    ) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        _host(AppButton(label: 'Save', onPressed: () => completer.future)),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(AppButton));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'A second tap must not fire the save twice.',
      );

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });

    testWidgets('comes back when the work throws', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        _host(AppButton(label: 'Save', onPressed: () => completer.future)),
      );

      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.completeError(StateError('no network'));
      await tester.pumpAndSettle();
      // Claimed before asserting anything: the error is not swallowed by the
      // button, it propagates past it exactly as an un-wrapped await would.
      // This test is only about the button surviving it.
      expect(tester.takeException(), isStateError);

      // The button is alive again. A dead button after a failed save is
      // worse than the failure — the operator cannot retry.
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a synchronous callback does not spin', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(AppButton(label: 'Filter', onPressed: () => taps++)),
      );

      await tester.tap(find.byType(AppButton));
      await tester.pump();

      expect(taps, 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the caller can force busy without owning the callback', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(AppButton(label: 'Save', busy: true, onPressed: () {})),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    });

    testWidgets('a null callback is simply disabled', (tester) async {
      await tester.pumpWidget(
        _host(const AppButton(label: 'Save', onPressed: null)),
      );

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('AppButton appearance', () {
    testWidgets('a danger button does not look like a save button', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          Column(
            children: <Widget>[
              AppButton(label: 'Save', onPressed: () {}),
              AppButton(
                label: 'Delete',
                tone: AppTone.danger,
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      Color fillOf(int index) {
        final buttons = tester.widgetList<FilledButton>(
          find.byType(FilledButton),
        );
        const states = <WidgetState>{};
        return buttons
            .elementAt(index)
            .style!
            .backgroundColor!
            .resolve(states)!;
      }

      expect(fillOf(0), isNot(fillOf(1)));
    });

    testWidgets('every variant clears the tap-target minimum', (tester) async {
      for (final variant in AppButtonVariant.values) {
        await tester.pumpWidget(
          _host(AppButton(label: 'Go', variant: variant, onPressed: () {})),
        );
        expect(
          tester.getSize(find.byType(AppButton)).height,
          greaterThanOrEqualTo(TapTarget.min),
          reason: '$variant is below the minimum a thumb needs.',
        );
      }
    });

    testWidgets('announces that it is working', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(AppButton(label: 'Save', busy: true, onPressed: () {})),
      );

      expect(
        tester.getSemantics(find.byType(AppButton)).hint,
        contains('Working'),
      );
      handle.dispose();
    });
  });

  group('showAppSheet', () {
    // Deliberately not an AppButton: a sheet's future completes only when the
    // sheet closes, so an AppButton opener would sit in its busy state for the
    // whole life of the sheet. That is the correct behaviour — it blocks a
    // double-open — but it is the button's behaviour, not the sheet's, and it
    // belongs in the button's own tests.
    Widget opener(Widget content) {
      return _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showAppSheet<void>(context: context, builder: (_) => content),
            child: const Text('Open'),
          ),
        ),
      );
    }

    testWidgets('never opens taller than the screen it is on', (tester) async {
      await tester.pumpWidget(opener(const SizedBox(height: 4000)));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final screen = tester.getSize(find.byType(MaterialApp)).height;
      expect(
        tester.getSize(find.byType(AppSheet)).height,
        lessThanOrEqualTo(screen * 0.9),
        reason: 'One old call site hardcoded 680, taller than a small phone.',
      );
    });

    testWidgets('content that overflows scrolls instead of clipping', (
      tester,
    ) async {
      await tester.pumpWidget(opener(const SizedBox(height: 4000)));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the header reads as a header, subtitle optional', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const AppSheetHeader(title: 'Collect payment')),
      );

      expect(find.text('Collect payment'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(AppSheetHeader)).label,
        contains('Collect payment'),
      );
      handle.dispose();
    });
  });
}
