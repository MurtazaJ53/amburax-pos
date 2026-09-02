import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:local_auth/local_auth.dart';

import '../database/mobile_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Keys in the local settings KV store (survive app restarts; cleared only on a
/// full data wipe, which also logs the user out).
const String _kPinHashKey = 'app_lock_pin_hash';
const String _kBiometricKey = 'app_lock_biometric';

String _hashPin(String pin) =>
    sha256.convert(utf8.encode('bhub-lock:${pin.trim()}')).toString();

/// Holds whether an app-open PIN is configured and whether the app is currently
/// locked. The gate widget watches this to overlay the lock screen.
class AppLockController extends ChangeNotifier {
  AppLockController(this._shopRepository) {
    _load();
  }

  final ShopRepository _shopRepository;

  String? _pinHash;
  bool _biometricEnabled = false;
  bool _loaded = false;
  // Start locked if a PIN turns out to be set, so a cold launch is protected.
  bool _locked = true;

  bool get isLoaded => _loaded;
  bool get isEnabled => _pinHash != null && _pinHash!.isNotEmpty;
  bool get biometricEnabled => _biometricEnabled;

  /// True only when a PIN is set AND we haven't been unlocked yet.
  bool get isLocked => isEnabled && _locked;

  Future<void> _load() async {
    _pinHash = await _shopRepository.readSetting(_kPinHashKey);
    _biometricEnabled =
        (await _shopRepository.readSetting(_kBiometricKey)) == '1';
    // Nothing to protect if no PIN was ever set.
    if (!isEnabled) _locked = false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setPin(String pin, {required bool biometric}) async {
    _pinHash = _hashPin(pin);
    _biometricEnabled = biometric;
    await _shopRepository.writeSetting(_kPinHashKey, _pinHash!);
    await _shopRepository.writeSetting(_kBiometricKey, biometric ? '1' : '0');
    _locked = false;
    notifyListeners();
  }

  Future<void> clearPin() async {
    _pinHash = null;
    _biometricEnabled = false;
    await _shopRepository.writeSetting(_kPinHashKey, '');
    await _shopRepository.writeSetting(_kBiometricKey, '0');
    _locked = false;
    notifyListeners();
  }

  bool verify(String pin) {
    if (!isEnabled) return true;
    if (_hashPin(pin) == _pinHash) {
      _locked = false;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Re-lock (called when the app is backgrounded), so the next open re-prompts.
  void lock() {
    if (isEnabled && !_locked) {
      _locked = true;
      notifyListeners();
    }
  }

  void unlock() {
    if (_locked) {
      _locked = false;
      notifyListeners();
    }
  }
}

final appLockControllerProvider = ChangeNotifierProvider<AppLockController>((
  ref,
) {
  return AppLockController(ref.watch(shopRepositoryProvider));
});

/// Settings panel to turn the app-open PIN on/off and toggle biometric unlock.
/// Self-contained so it can drop into any settings screen for any role.
class AppLockPanel extends ConsumerWidget {
  const AppLockPanel({super.key});

  Future<void> _setPin(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<(String, bool)>(
      context: context,
      builder: (_) => const _SetPinDialog(),
    );
    if (result == null) return;
    await ref
        .read(appLockControllerProvider)
        .setPin(result.$1, biometric: result.$2);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('App lock enabled.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockControllerProvider);
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.lock_rounded, color: AppPalette.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'App PIN lock',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: (lock.isEnabled ? AppPalette.success : colors.border)
                      .withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  lock.isEnabled ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: lock.isEnabled
                        ? AppPalette.success
                        : colors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Require a 4–6 digit PIN every time the app opens. Fingerprint/face '
            'unlock can be used as a shortcut.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _setPin(context, ref),
                  icon: const Icon(Icons.pin_rounded),
                  label: Text(lock.isEnabled ? 'Change PIN' : 'Set PIN'),
                ),
              ),
              if (lock.isEnabled) ...<Widget>[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    await ref.read(appLockControllerProvider).clearPin();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('App lock removed.')),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.error,
                    side: const BorderSide(color: AppPalette.error),
                  ),
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('Remove'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog();

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _biometric = true;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _pin.text.trim();
    if (pin.length < 4 || pin.length > 6) {
      setState(() => _error = 'PIN must be 4–6 digits.');
      return;
    }
    if (pin != _confirm.text.trim()) {
      setState(() => _error = 'PINs do not match.');
      return;
    }
    Navigator.pop<(String, bool)>(context, (pin, _biometric));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set app PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'New PIN (4–6 digits)',
              counterText: '',
            ),
          ),
          TextField(
            controller: _confirm,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Confirm PIN',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _biometric,
            onChanged: (v) => setState(() => _biometric = v),
            title: const Text('Allow fingerprint / face unlock'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(
                color: AppPalette.error,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Wraps the whole app: when a PIN is set and the app is locked, it paints a
/// full-screen lock over everything. Also re-locks whenever the app is
/// backgrounded so re-opening always asks for the PIN.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(appLockControllerProvider).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockControllerProvider);
    return Stack(
      children: <Widget>[
        widget.child,
        if (lock.isLocked)
          Positioned.fill(
            child: _LockScreen(
              biometricEnabled: lock.biometricEnabled,
              onVerify: (pin) =>
                  ref.read(appLockControllerProvider).verify(pin),
              onBiometricSuccess: () =>
                  ref.read(appLockControllerProvider).unlock(),
            ),
          ),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({
    required this.biometricEnabled,
    required this.onVerify,
    required this.onBiometricSuccess,
  });

  final bool biometricEnabled;
  final bool Function(String pin) onVerify;
  final VoidCallback onBiometricSuccess;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  String _entry = '';
  String? _error;
  bool _promptedBiometric = false;

  @override
  void initState() {
    super.initState();
    if (widget.biometricEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  Future<void> _tryBiometric() async {
    if (_promptedBiometric) return;
    _promptedBiometric = true;
    try {
      final auth = LocalAuthentication();
      final canCheck =
          await auth.isDeviceSupported() && await auth.canCheckBiometrics;
      if (!canCheck) return;
      final ok = await auth.authenticate(
        localizedReason: 'Unlock Business Hub',
        biometricOnly: true,
      );
      if (ok) {
        // A successful fingerprint/face unlocks directly (we can't recover the
        // numeric PIN from biometrics).
        widget.onBiometricSuccess();
      }
    } catch (_) {
      // Fall back to PIN entry silently.
    }
  }

  void _tap(String digit) {
    if (_entry.length >= 6) return;
    setState(() {
      _entry += digit;
      _error = null;
    });
    if (_entry.length >= 4) {
      // Auto-submit at 4; still allow up to 6.
      _submit();
    }
  }

  void _backspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _submit() {
    if (widget.onVerify(_entry)) return;
    setState(() {
      _error = 'Wrong PIN. Try again.';
      _entry = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
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
                      Icons.lock_rounded,
                      color: AppPalette.primary,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Enter your PIN',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(6, (i) {
                      final filled = i < _entry.length;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: filled ? AppPalette.primary : colors.border,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 20,
                    child: _error == null
                        ? null
                        : Text(
                            _error!,
                            style: const TextStyle(
                              color: AppPalette.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  _PinPad(
                    onDigit: _tap,
                    onBackspace: _backspace,
                    onBiometric: widget.biometricEnabled ? _tryBiometric : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, Widget? icon}) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Material(
            color: AppColors.of(context).surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap ?? () => onDigit(label),
              child: Center(
                child:
                    icon ??
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[key('1'), key('2'), key('3')],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[key('4'), key('5'), key('6')],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[key('7'), key('8'), key('9')],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            onBiometric == null
                ? const SizedBox(width: 88, height: 88)
                : key(
                    '',
                    onTap: onBiometric,
                    icon: const Icon(Icons.fingerprint_rounded, size: 30),
                  ),
            key('0'),
            key(
              '',
              onTap: onBackspace,
              icon: const Icon(Icons.backspace_outlined, size: 24),
            ),
          ],
        ),
      ],
    );
  }
}
