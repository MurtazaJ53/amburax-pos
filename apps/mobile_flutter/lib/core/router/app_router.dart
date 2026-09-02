import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_gate_screen.dart';
import '../../features/customers/presentation/customers_screen_v3.dart';
import '../../features/inventory/presentation/category_management_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen_v3.dart';
import '../../features/history/presentation/history_screen.dart';
import '../../features/inventory/presentation/inventory_screen_v3.dart';
import '../../features/pos/presentation/pos_screen_v3.dart';
import '../../features/settings/presentation/settings_backup_screen.dart';
import '../../features/settings/presentation/settings_business_screen.dart';
import '../../features/settings/presentation/settings_import_screen.dart';
import '../../features/settings/presentation/settings_attendance_screen.dart';
import '../../features/settings/presentation/settings_expenses_screen.dart';
import '../../features/settings/presentation/settings_billing_screen.dart';
import '../../features/customers/presentation/khata_collection_screen.dart';
import '../../features/inventory/presentation/purchase_orders_screen.dart';
import '../../features/inventory/presentation/reorder_list_screen.dart';
import '../../features/inventory/presentation/stock_transfers_screen.dart';
import '../../features/inventory/presentation/stocktake_screen.dart';
import '../../features/reports/presentation/day_book_screen.dart';
import '../../features/settings/presentation/notifications_screen.dart';
import '../../features/onboarding/presentation/setup_wizard_screen.dart';
import '../../features/reports/presentation/business_pulse_screen.dart';
import '../../features/reports/presentation/dead_stock_screen.dart';
import '../../features/reports/presentation/staff_performance_screen.dart';
import '../../features/settings/presentation/data_health_screen.dart';
import '../../features/settings/presentation/settings_language_screen.dart';
import '../../features/settings/presentation/settings_purchases_screen.dart';
import '../../features/settings/presentation/settings_pulse_screen.dart';
import '../../features/settings/presentation/settings_security_screen.dart';
import '../../features/settings/presentation/settings_sessions_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/settings_staff_screen.dart';
import '../../features/settings/presentation/settings_team_screen.dart';
import '../../features/reports/presentation/day_close_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/shell/presentation/mobile_shell_screen.dart';

final GlobalKey<NavigatorState> appRootNavigatorKey =
    GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: appRootNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthGateScreen()),
      // First-run setup. Reached from the dashboard prompt rather than forced,
      // so an existing shop is never made to walk through it.
      GoRoute(
        path: '/setup',
        parentNavigatorKey: appRootNavigatorKey,
        builder: (context, state) => const SetupWizardScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MobileShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: mobileShellBranchNavigatorKeys[0],
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (context, state) => const DashboardScreenV3(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: mobileShellBranchNavigatorKeys[1],
            routes: [
              GoRoute(
                path: '/inventory',
                builder: (context, state) => const InventoryScreenV3(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: mobileShellBranchNavigatorKeys[2],
            routes: [
              GoRoute(
                path: '/customers',
                builder: (context, state) => const CustomersScreenV3(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: mobileShellBranchNavigatorKeys[3],
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: mobileShellBranchNavigatorKeys[4],
            routes: [
              GoRoute(
                path: '/pos',
                builder: (context, state) => const PosScreenV3(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: appRootNavigatorKey,
        path: '/settings',
        pageBuilder: (context, state) =>
            const NoTransitionPage<void>(child: SettingsScreen()),
        routes: [
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'business',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsBusinessScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'backup',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsBackupScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'import',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsImportScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'staff-performance',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: StaffPerformanceScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'pulse',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: BusinessPulseScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'dead-stock',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: DeadStockScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'data-health',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: DataHealthScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'alerts',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: NotificationsScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'day-book',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: DayBookScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'stocktake',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: StocktakeScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'transfers',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: StockTransfersScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'purchase-orders',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: PurchaseOrdersScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'reorder',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: ReorderListScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'collect',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: KhataCollectionScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'language',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsLanguageScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'billing',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsBillingScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'security',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsSecurityScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'staff',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsStaffScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'team',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsTeamScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'attendance',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsAttendanceScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'expenses',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsExpensesScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'purchases',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsPurchasesScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'sessions',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsSessionsScreen()),
          ),
          GoRoute(
            parentNavigatorKey: appRootNavigatorKey,
            path: 'pulse',
            pageBuilder: (context, state) =>
                const NoTransitionPage<void>(child: SettingsPulseScreen()),
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: appRootNavigatorKey,
        path: '/reports',
        pageBuilder: (context, state) =>
            const NoTransitionPage<void>(child: ReportsScreen()),
      ),
      GoRoute(
        parentNavigatorKey: appRootNavigatorKey,
        path: '/day-close',
        pageBuilder: (context, state) =>
            const NoTransitionPage<void>(child: DayCloseScreen()),
      ),
      GoRoute(
        parentNavigatorKey: appRootNavigatorKey,
        path: '/categories',
        pageBuilder: (context, state) =>
            const NoTransitionPage<void>(child: CategoryManagementScreen()),
      ),
      GoRoute(path: '/home', redirect: (context, state) => '/dashboard'),
    ],
  );
});
