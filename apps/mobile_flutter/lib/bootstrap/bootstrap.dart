import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../app/app.dart';
import '../core/diagnostics/crash_logger.dart';
import '../core/theme/app_colors.dart';

/// Cloud crash reporting.
///
/// A Sentry DSN is a write-only ingest endpoint — it is designed to ship inside
/// the client and cannot read data back — so it lives here as the default
/// rather than being passed at every build, which is how it ended up unset (and
/// crash reporting silently off) in the first place. Override per build with
///   --dart-define SENTRY_DSN=...
const String _sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue:
      'https://1a090a583f745386a58e8513d4b6e549@o4511852648202240.ingest.de.sentry.io/4511852669894736',
);

Future<void> bootstrapApplication() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrashLogger.init();

  ErrorWidget.builder = (details) {
    debugPrint('Business Hub widget error: ${details.exception}');
    CrashLogger.record(details.exception, details.stack, kind: 'widget');
    return const _FatalSurfaceFallback();
  };

  // Our on-device crash log runs first; Sentry (when configured) chains onto
  // these handlers rather than replacing them.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Business Hub Flutter error: ${details.exception}');
    CrashLogger.record(details.exception, details.stack, kind: 'flutter');
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    debugPrint('Business Hub platform error: $error');
    CrashLogger.record(error, stackTrace, kind: 'platform');
    return true;
  };

  void runTheApp() {
    runApp(const ProviderScope(child: BusinessHubMobileApp()));
  }

  if (_sentryDsn.isEmpty) {
    runTheApp();
    return;
  }

  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn;
    // No performance tracing: this is a POS on cheap phones and metered
    // data. We want crashes, not a stream of spans.
    options.tracesSampleRate = 0.0;
    options.environment = kReleaseMode ? 'production' : 'debug';
    // A shop's bills and customer names must never leave the device, so
    // don't let the SDK attach user/request data automatically.
    options.sendDefaultPii = false;
  }, appRunner: runTheApp);
}

class _FatalSurfaceFallback extends StatelessWidget {
  const _FatalSurfaceFallback();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ColoredBox(
      color: colors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceStrong,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF6B67).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFEF6B67),
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This screen hit a runtime problem',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Business Hub stopped this view from turning into a blank page. Please reopen the screen or refresh the workspace.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.black.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
