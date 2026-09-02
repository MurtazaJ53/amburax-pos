import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/runtime/mobile_runtime_config.dart';
import '../../../core/region/gst_states.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../pos/presentation/pos_scanner_sheet.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({super.key});

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen>
    with SingleTickerProviderStateMixin {
  final _pinController = TextEditingController();
  // Cloud (JWT) login — start empty so users enter their own credentials.
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // Sign-up (create a new shop).
  final _regOwnerController = TextEditingController();
  final _regBusinessController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regMobileController = TextEditingController();
  String _regStateCode = '';
  final _regGstinController = TextEditingController();
  String _regBusinessType = 'retail';
  // Join an existing shop with an invite code.
  final _joinCodeController = TextEditingController();
  final _joinNameController = TextEditingController();
  final _joinPasswordController = TextEditingController();
  bool _showRegister = false;
  bool _showJoin = false;
  bool _isLoggingIn = false;
  bool _hasPin = true; // assume returning user until checked
  bool get _cloudMode => MobileRuntimeConfig.backendAuthMode == 'jwt';
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _loadHasPin();
  }

  Future<void> _loadHasPin() async {
    final has = await ref.read(mobileSessionProvider.notifier).hasPin();
    if (mounted) setState(() => _hasPin = has);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pinController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _regOwnerController.dispose();
    _regBusinessController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regMobileController.dispose();
    _regGstinController.dispose();
    _joinCodeController.dispose();
    _joinNameController.dispose();
    _joinPasswordController.dispose();
    super.dispose();
  }

  /// Open the camera scanner and drop the invite token into the code field.
  /// Accepts a QR of the deep link (businesshub://join?token=...), an https
  /// invite URL, or a plain code — all resolve to the same token.
  Future<void> _scanInviteQr() async {
    final raw = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PosScannerSheet(),
    );
    if (!mounted || raw == null || raw.trim().isEmpty) return;
    setState(() => _joinCodeController.text = _extractInviteToken(raw.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite scanned. Set your name and password to join.'),
      ),
    );
  }

  String _extractInviteToken(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final fromQuery = uri.queryParameters['token'];
      if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
      if (uri.pathSegments.isNotEmpty && (uri.hasScheme || raw.contains('/'))) {
        return uri.pathSegments.last;
      }
    }
    return raw;
  }

  Future<void> _handleJoin() async {
    if (_joinCodeController.text.trim().isEmpty ||
        _joinPasswordController.text.length < 8) {
      _triggerShake();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter the invite code and a password of 8+ characters.',
          ),
        ),
      );
      return;
    }
    setState(() => _isLoggingIn = true);
    final error = await ref
        .read(mobileSessionProvider.notifier)
        .cloudAcceptInvite(
          code: _joinCodeController.text,
          name: _joinNameController.text,
          password: _joinPasswordController.text,
        );
    if (!mounted) return;
    setState(() => _isLoggingIn = false);
    if (error != null) {
      _triggerShake();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Joined! Welcome to the team.')),
      );
    }
  }

  Future<void> _handleRegister() async {
    if (_regOwnerController.text.trim().isEmpty ||
        _regBusinessController.text.trim().isEmpty ||
        _regEmailController.text.trim().isEmpty ||
        _regPasswordController.text.length < 8) {
      _triggerShake();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Fill name, business, email and a password of 8+ characters.',
          ),
        ),
      );
      return;
    }
    setState(() => _isLoggingIn = true);
    final error = await ref
        .read(mobileSessionProvider.notifier)
        .cloudRegister(
          ownerName: _regOwnerController.text,
          email: _regEmailController.text,
          password: _regPasswordController.text,
          businessName: _regBusinessController.text,
          mobile: _regMobileController.text,
          businessType: _regBusinessType,
          stateCode: _regStateCode,
          gstin: _regGstinController.text,
        );
    if (!mounted) return;
    setState(() => _isLoggingIn = false);
    if (error != null) {
      _triggerShake();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shop created! Welcome to Business Hub.')),
      );
    }
  }

  Future<void> _handleCloudLogin() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      _triggerShake();
      return;
    }
    setState(() => _isLoggingIn = true);
    final error = await ref
        .read(mobileSessionProvider.notifier)
        .cloudLogin(_emailController.text, _passwordController.text);
    if (!mounted) return;
    setState(() => _isLoggingIn = false);
    if (error != null) {
      _triggerShake();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _triggerShake() {
    HapticFeedback.mediumImpact();
    _shakeController.forward(from: 0);
  }

  void _handleLogin() async {
    // Old-app behaviour: an incomplete PIN shakes the field instead of
    // silently doing nothing.
    if (_pinController.text.length < 4) {
      _triggerShake();
      return;
    }

    setState(() => _isLoggingIn = true);

    final ok = await ref
        .read(mobileSessionProvider.notifier)
        .login(_pinController.text);

    if (!mounted) return;
    setState(() => _isLoggingIn = false);
    if (!ok) {
      _pinController.clear();
      _triggerShake();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect PIN. Try again.')),
      );
    }
  }

  InputDecoration _fieldDecoration(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.of(context).backgroundSoft,
    isDense: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );

  Widget _buildCloudLoginPanel(BuildContext context) {
    final colors = AppColors.of(context);
    return AppPanel(
      title: 'Cloud Sign-in',
      action: const MobileTag(label: 'CLOUD', icon: Icons.cloud_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            'Sign in to sync with the cloud backend.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: _fieldDecoration('Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: _fieldDecoration('Password'),
            onSubmitted: (_) => _handleCloudLogin(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoggingIn ? null : _handleCloudLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoggingIn
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'SIGN IN',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: _isLoggingIn
                    ? null
                    : () => setState(() => _showRegister = true),
                child: const Text("Create a shop"),
              ),
              TextButton(
                onPressed: _isLoggingIn
                    ? null
                    : () => setState(() => _showJoin = true),
                child: const Text("Join with a code"),
              ),
            ],
          ),
          Text(
            'First request may take ~40s while the free server wakes up.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudRegisterPanel(BuildContext context) {
    final colors = AppColors.of(context);
    return AppPanel(
      title: 'Create your shop',
      action: const MobileTag(
        label: 'SIGN UP',
        icon: Icons.storefront_outlined,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            'Set up a new business workspace in under a minute.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _regOwnerController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration('Your name *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regBusinessController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration('Business name *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regEmailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: _fieldDecoration('Email *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regPasswordController,
            obscureText: true,
            decoration: _fieldDecoration('Password (8+ characters) *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regMobileController,
            keyboardType: TextInputType.phone,
            decoration: _fieldDecoration('Mobile (optional)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _regBusinessType,
                  isDense: true,
                  decoration: _fieldDecoration('Type'),
                  items: const [
                    DropdownMenuItem(value: 'retail', child: Text('Retail')),
                    DropdownMenuItem(
                      value: 'wholesale',
                      child: Text('Wholesale'),
                    ),
                    DropdownMenuItem(value: 'grocery', child: Text('Grocery')),
                    // Pharmacy and Restaurant are deliberately absent until the
                    // app does what picking them implies — batch and expiry for
                    // a pharmacy, tables and orders for a restaurant. Both are
                    // planned. The website's list must match this one.
                    DropdownMenuItem(value: 'service', child: Text('Service')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) =>
                      setState(() => _regBusinessType = v ?? 'retail'),
                ),
              ),
              const SizedBox(width: 12),
              // A named list, not a two-digit box. This code decides
              // CGST+SGST versus IGST on every bill, and nobody knows their
              // state code by heart — the old field invited a state name or a
              // missing leading zero, and rejected neither.
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _regStateCode.isEmpty ? null : _regStateCode,
                  isExpanded: true,
                  decoration: _fieldDecoration('State (for GST)'),
                  items: <DropdownMenuItem<String>>[
                    for (final s in kGstStates)
                      DropdownMenuItem<String>(
                        value: s.code,
                        child: Text(
                          '${s.name} (${s.code})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _regStateCode = v ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _regGstinController,
            textCapitalization: TextCapitalization.characters,
            decoration: _fieldDecoration('GSTIN (optional)'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoggingIn ? null : _handleRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoggingIn
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'CREATE SHOP',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isLoggingIn
                ? null
                : () => setState(() => _showRegister = false),
            child: const Text('Already have an account? Sign in'),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudJoinPanel(BuildContext context) {
    final colors = AppColors.of(context);
    return AppPanel(
      title: 'Join a shop',
      action: const MobileTag(label: 'INVITE', icon: Icons.group_add_outlined),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            'Enter the invite code from your email to join your team.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _isLoggingIn ? null : _scanInviteQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan invite QR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.primary,
                side: const BorderSide(color: AppPalette.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            textCapitalization: TextCapitalization.sentences,
            controller: _joinCodeController,
            autocorrect: false,
            decoration: _fieldDecoration('Invite code *'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _joinNameController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration('Your name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _joinPasswordController,
            obscureText: true,
            decoration: _fieldDecoration('Set a password (8+ characters) *'),
            onSubmitted: (_) => _handleJoin(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoggingIn ? null : _handleJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isLoggingIn
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'JOIN SHOP',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _isLoggingIn
                ? null
                : () => setState(() => _showJoin = false),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final sessionAsync = ref.watch(mobileSessionProvider);

    return sessionAsync.when(
      loading: () => const _AuthScaffold(
        child: _BrandedStatus(
          icon: Icons.offline_bolt_rounded,
          eyebrow: 'Local vault',
          title: 'Opening Business Hub',
          subtitle: 'Preparing the local workspace before any cloud sync.',
        ),
      ),
      error: (error, _) => _AuthScaffold(
        child: _BrandedStatus(
          icon: Icons.error_outline_rounded,
          eyebrow: 'Startup issue',
          title: 'Workspace could not open',
          subtitle: error.toString(),
        ),
      ),
      data: (session) {
        if (session != null && session.hasShop) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.go(session.defaultRoute);
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // SHOW LOGIN SCREEN IF NO SESSION
        if (_cloudMode) {
          return _AuthScaffold(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BrandHero(),
                const SizedBox(height: 24),
                if (_showJoin)
                  _buildCloudJoinPanel(context)
                else if (_showRegister)
                  _buildCloudRegisterPanel(context)
                else
                  _buildCloudLoginPanel(context),
              ],
            ),
          );
        }

        return _AuthScaffold(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BrandHero(),
              const SizedBox(height: 28),
              AppPanel(
                title: _hasPin ? 'Staff Login' : 'Set up PIN',
                action: MobileTag(
                  label: _hasPin ? 'SECURE' : 'FIRST TIME',
                  icon: Icons.lock_outline,
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      _hasPin
                          ? 'Enter your PIN to unlock the POS terminal.'
                          : 'Choose a 4-digit PIN to secure this terminal. You will use it every time you sign in.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _ShakeBuilder(
                      controller: _shakeController,
                      child: TextField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        maxLength: 4,
                        style: const TextStyle(
                          fontSize: 24,
                          letterSpacing: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          hintText: '----',
                          counterText: '',
                          filled: true,
                          fillColor: colors.backgroundSoft,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => _handleLogin(),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [
                              AppPalette.primaryLight,
                              AppPalette.primary,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppPalette.primary.withValues(alpha: 0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoggingIn ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoggingIn
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _hasPin
                                      ? 'UNLOCK TERMINAL'
                                      : 'SET PIN & UNLOCK',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Gradient brand hero echoing the legacy web login: sky-blue logo badge,
/// wordmark and tagline.
class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              colors: [AppPalette.primaryLight, AppPalette.primaryDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppPalette.primary.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const Icon(
            Icons.storefront_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Business Hub',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Point of sale & business command center',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Horizontal shake driven by an [AnimationController]; used for invalid input.
class _ShakeBuilder extends StatelessWidget {
  const _ShakeBuilder({required this.controller, required this.child});

  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // 3 quick oscillations that decay to zero as the controller completes.
        final dx =
            math.sin(controller.value * math.pi * 6) *
            10 *
            (1 - controller.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: child,
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.child});

  final Widget child;

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
        child: Stack(
          children: <Widget>[
            // Sky-blue brand aura (matches the legacy app palette).
            const Positioned(
              top: -80,
              left: -40,
              child: _AuraBlob(size: 240, color: Color(0x330EA5E9)),
            ),
            const Positioned(
              bottom: -80,
              right: -42,
              child: _AuraBlob(size: 240, color: Color(0x2638BDF8)),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: child,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandedStatus extends StatelessWidget {
  const _BrandedStatus({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final theme = Theme.of(context);
    return AppPanel(
      title: title,
      action: MobileTag(label: eyebrow.toUpperCase(), icon: icon),
      child: Column(
        children: <Widget>[
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(icon, color: AppPalette.primary, size: 36),
          ),
          const SizedBox(height: 20),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ],
      ),
    );
  }
}

class _AuraBlob extends StatelessWidget {
  const _AuraBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
