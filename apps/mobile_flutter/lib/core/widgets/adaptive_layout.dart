import 'package:flutter/material.dart';

/// Provides a unified layout builder that adapts to Phone, Tablet, and Desktop breakpoints.
///
/// Breakpoints:
/// - Phone: width < 600
/// - Tablet: 600 <= width < 900
/// - Desktop: width >= 900
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    super.key,
    required this.phone,
    required this.tablet,
    required this.desktop,
  });

  final WidgetBuilder phone;
  final WidgetBuilder tablet;
  final WidgetBuilder desktop;

  static bool isPhone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600;
  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600 &&
      MediaQuery.sizeOf(context).width < 900;
  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return desktop(context);
        } else if (constraints.maxWidth >= 600) {
          return tablet(context);
        } else {
          return phone(context);
        }
      },
    );
  }
}
