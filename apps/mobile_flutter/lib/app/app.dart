import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/i18n/locale_controller.dart';
import '../l10n/app_localizations.dart';

import '../core/database/local_database.dart';
import '../core/router/app_router.dart';
import '../core/security/app_lock.dart';
import '../core/sync/mobile_sync_coordinator.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_controller.dart';

final startupBootstrapProvider = FutureProvider<void>((ref) async {
  await LocalDatabaseController.instance.initialize();
});

class BusinessHubMobileApp extends ConsumerWidget {
  const BusinessHubMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupBootstrapProvider);
    final themeMode = ref.watch(themeModeProvider);

    return startup.when(
      loading: () => MaterialApp(
        title: 'Business Hub',
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: AppTheme.light,
        darkTheme: AppTheme.light,
        home: const _StartupBootScreen(),
      ),
      error: (error, _) => MaterialApp(
        title: 'Business Hub',
        debugShowCheckedModeBanner: false,
        themeMode: themeMode,
        theme: AppTheme.light,
        darkTheme: AppTheme.light,
        home: _StartupFailedScreen(
          message: error.toString(),
          onRetry: () => ref.invalidate(startupBootstrapProvider),
        ),
      ),
      data: (_) {
        ref.watch(localDatabaseProvider);
        ref.watch(mobileSyncCoordinatorProvider);
        final router = ref.watch(appRouterProvider);
        return MaterialApp.router(
          title: 'Business Hub',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: AppTheme.light,
          darkTheme: AppTheme.light,
          // null locale = follow the device, so a phone already set to
          // Gujarati opens in Gujarati without hunting through settings.
          locale: ref.watch(localeControllerProvider).locale,
          supportedLocales: kSupportedLocales,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            L.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
          // Overlay the PIN lock above every route when one is configured.
          builder: (context, child) =>
              AppLockGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

class _StartupBootScreen extends StatelessWidget {
  const _StartupBootScreen();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              colors.background,
              colors.backgroundSoft,
              colors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppPalette.panel,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppPalette.lineSoft),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x40000000),
                        blurRadius: 28,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppPalette.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            color: AppPalette.primary,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Starting Business Hub',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.7,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Opening your local vault and workspace session.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 20),
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupFailedScreen extends StatelessWidget {
  const _StartupFailedScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              colors.background,
              colors.backgroundSoft,
              colors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppPalette.panel,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppPalette.lineSoft),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: AppPalette.coral.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            color: AppPalette.coral,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Startup needs attention',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w600,
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.tonalIcon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry startup'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
