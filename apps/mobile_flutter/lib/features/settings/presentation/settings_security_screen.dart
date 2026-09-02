import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/runtime/mobile_runtime_config.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../ui/ui.dart';

class SettingsSecurityScreen extends ConsumerStatefulWidget {
  const SettingsSecurityScreen({super.key});

  @override
  ConsumerState<SettingsSecurityScreen> createState() =>
      _SettingsSecurityScreenState();
}

class _SettingsSecurityScreenState
    extends ConsumerState<SettingsSecurityScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _busy = false;
  String? _message;
  UserMfaStatus? _status;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.isOwnerLike) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final status = await ref
          .read(backendApiClientProvider)
          .getUserMfaStatus(user: session.user);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _beginEnrollment() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null) {
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final status = await ref
          .read(backendApiClientProvider)
          .beginUserMfaEnrollment(user: session.user);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = status;
        _message = 'Authenticator setup started.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _verify(String purpose) async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null) {
      return;
    }
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _message = 'Enter the 6-digit authentication code first.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await ref
          .read(backendApiClientProvider)
          .verifyUserMfaCode(
            user: session.user,
            payload: UserMfaVerifyPayload(purpose: purpose, code: code),
          );
      await ref
          .read(shopRepositoryProvider)
          .saveMfaVerifiedUntil(result.verifiedUntil);
      if (!mounted) {
        return;
      }
      _codeController.clear();
      setState(() {
        _status = result.status;
        _message = purpose == 'enroll'
            ? 'MFA is now enabled for this account.'
            : 'Security verification refreshed.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _disable() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null) {
      return;
    }
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() {
        _message = 'Enter the current authentication code to disable MFA.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final status = await ref
          .read(backendApiClientProvider)
          .disableUserMfa(user: session.user, code: code);
      await ref.read(shopRepositoryProvider).saveMfaVerifiedUntil(null);
      if (!mounted) {
        return;
      }
      _codeController.clear();
      setState(() {
        _status = status;
        _message = 'MFA disabled. Sensitive surfaces will lock again.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final verifiedUntil = ref
        .watch(mobileMfaVerifiedUntilProvider)
        .asData
        ?.value;
    final hasFreshWindow =
        verifiedUntil != null && verifiedUntil.isAfter(DateTime.now());

    if (session == null) {
      return AppScreen(
        scrollable: false,
        title: 'Security',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            AppPanel(
              title: 'Loading security',
              child: AppEmptyState(
                icon: Icons.sync_rounded,
                title: 'Checking account access',
                body:
                    'Business Hub is loading the current signed-in owner/admin account before opening mobile security controls.',
              ),
            ),
          ],
        ),
      );
    }

    if (!MobileRuntimeConfig.backendSyncEnabled) {
      return AppScreen(
        scrollable: false,
        title: 'Security',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            AppLockPanel(),
            SizedBox(height: 18),
            AppScreenLead(
              title: 'Local owner mode is active',
              subtitle:
                  'Backend deployment is paused, so MFA, passkeys, remote session wipe, and server-side session invalidation stay disabled in this APK.',
              tags: <Widget>[
                AppTag(
                  label: 'LOCAL-FIRST',
                  icon: Icons.lock_open_rounded,
                  tone: AppTone.warning,
                ),
              ],
            ),
            SizedBox(height: 18),
            AppPanel(
              title: 'What works now',
              child: AppEmptyState(
                icon: Icons.phone_android_rounded,
                title: 'Device vault is unlocked locally',
                body:
                    'Inventory, POS, customers, history, owner role, and local team baseline are available without cloud auth. Turn on backend sync later to enable enterprise security controls.',
              ),
            ),
          ],
        ),
      );
    }

    if (_status == null && !_busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadStatus();
        }
      });
    }

    if (!session.isOwnerLike) {
      return AppScreen(
        scrollable: false,
        title: 'Security',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            AppLockPanel(),
            SizedBox(height: 18),
            AppPanel(
              title: 'Security controls stay with elevated roles',
              child: AppEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Owner/admin only',
                body:
                    'Daily operators should not manage MFA policy or sensitive business-control surfaces from mobile settings.',
              ),
            ),
          ],
        ),
      );
    }

    final status = _status;
    return AppScreen(
      scrollable: false,
      title: 'Security',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          AppScreenLead(
            title: 'Protect owner and admin controls',
            subtitle:
                'Use an authenticator app before opening Workspace plan, Advanced ops, or other sensitive business-control surfaces.',
            tags: <Widget>[
              AppTag(
                label: status == null
                    ? 'Loading'
                    : status.totpEnabled
                    ? 'MFA enabled'
                    : status.totpPendingEnrollment
                    ? 'Setup pending'
                    : 'MFA not set',
                icon: Icons.security_rounded,
                tone: AppTone.primary,
              ),
              AppTag(
                label: hasFreshWindow ? 'Window open' : 'Verify needed',
                icon: hasFreshWindow
                    ? Icons.verified_rounded
                    : Icons.lock_clock_rounded,
                tone: hasFreshWindow ? AppTone.success : AppTone.warning,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const AppLockPanel(),
          const SizedBox(height: 18),
          if (_message != null)
            AppPanel(
              title: 'Security signal',
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.black.withValues(alpha: 0.76),
                ),
              ),
            ),
          if (_message != null) const SizedBox(height: 18),
          AppPanel(
            title: 'Current posture',
            action: AppTag(
              label: hasFreshWindow ? 'Unlocked' : 'Locked',
              icon: hasFreshWindow
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
              tone: hasFreshWindow ? AppTone.success : AppTone.warning,
            ),
            child: Column(
              children: <Widget>[
                _SecurityRow(
                  label: 'Account',
                  value: status?.accountLabel ?? session.email,
                  icon: Icons.person_rounded,
                ),
                _SecurityRow(
                  label: 'Enabled',
                  value: status == null
                      ? 'Loading'
                      : status.totpEnabled
                      ? 'Yes'
                      : 'No',
                  icon: Icons.verified_user_rounded,
                ),
                _SecurityRow(
                  label: 'Last verified',
                  value:
                      status?.lastVerifiedAt?.toIso8601String() ??
                      'Not verified yet',
                  icon: Icons.schedule_rounded,
                ),
                _SecurityRow(
                  label: 'Secure window',
                  value: hasFreshWindow
                      ? 'Open until ${verifiedUntil.toLocal()}'
                      : 'Needs a fresh code',
                  icon: Icons.shield_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (status == null && _busy)
            const AppPanel(
              title: 'Loading security status',
              child: AppEmptyState(
                icon: Icons.sync_rounded,
                title: 'Checking MFA status',
                body:
                    'Business Hub is loading the current security posture for this owner/admin account.',
              ),
            )
          else if (status != null && !status.totpEnabled) ...<Widget>[
            AppPanel(
              title: 'Set up MFA',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Start authenticator setup, then verify the first code to enable MFA on this account.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black.withValues(alpha: 0.74),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (!status.totpPendingEnrollment)
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _beginEnrollment,
                      icon: const Icon(Icons.qr_code_rounded),
                      label: const Text('Start setup'),
                    )
                  else ...<Widget>[
                    _SecurityValueBlock(
                      label: 'Manual secret',
                      value: status.pendingManualSecret,
                    ),
                    const SizedBox(height: 12),
                    _SecurityValueBlock(
                      label: 'Authenticator link',
                      value: status.pendingOtpauthUri,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: status.pendingManualSecret),
                        );
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Manual secret copied.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy secret'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Verification code',
                        hintText: '123456',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _verify('enroll'),
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Verify and enable'),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (status != null) ...<Widget>[
            AppPanel(
              title: 'Verify owner/admin access',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Enter one current authenticator code to unlock protected mobile controls for this secure window.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black.withValues(alpha: 0.74),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Authentication code',
                      hintText: '123456',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _verify('challenge'),
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('Verify now'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppPanel(
              title: 'Disable MFA',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Disable MFA only if you are replacing the authenticator app. This immediately re-locks protected business-control surfaces.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.black.withValues(alpha: 0.74),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _busy ? null : _disable,
                    icon: const Icon(Icons.lock_reset_rounded),
                    label: const Text('Disable MFA'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          AppPanel(
            title: 'Protected surfaces',
            child: Column(
              children: <Widget>[
                _SecurityRow(
                  label: 'Workspace plan',
                  value: 'Owner/admin plan compare and upgrade posture',
                  icon: Icons.workspace_premium_rounded,
                ),
                _SecurityRow(
                  label: 'Advanced ops',
                  value: 'Recovery, rollout, and technical support tooling',
                  icon: Icons.tune_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to Settings'),
          ),
        ],
      ),
    );
  }
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: Colors.black.withValues(alpha: 0.68)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.black.withValues(alpha: 0.62),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityValueBlock extends StatelessWidget {
  const _SecurityValueBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.black.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.black.withValues(alpha: 0.9),
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
