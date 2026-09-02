import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

/// Manager-authorization gate for high-risk POS actions (void a sale, delete a
/// Khata entry, open the drawer without a sale). When enabled it asks for the
/// manager's **fingerprint** first (Android BiometricPrompt via local_auth) and
/// falls back to a manager **PIN** if biometrics aren't available/enrolled or
/// the user cancels the fingerprint scan.
class ManagerGate {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  /// Manager PIN, seeded from --dart-define BUSINESS_HUB_MANAGER_PIN.
  /// When empty, the gate is disabled (approval auto-granted) so a shop that
  /// hasn't configured a PIN isn't locked out.
  static const String _configuredPin = String.fromEnvironment(
    'BUSINESS_HUB_MANAGER_PIN',
  );

  static bool get isEnabled => _configuredPin.isNotEmpty;

  /// Constant-time-ish PIN check (compares every char so timing doesn't leak the
  /// matched prefix length).
  static bool verifyPin(String entered, {String? expected}) {
    final target = expected ?? _configuredPin;
    if (target.isEmpty) return true; // gate disabled
    if (entered.length != target.length) return false;
    var mismatch = 0;
    for (var i = 0; i < target.length; i++) {
      mismatch |= entered.codeUnitAt(i) ^ target.codeUnitAt(i);
    }
    return mismatch == 0;
  }

  /// Try a fingerprint/biometric check. Returns true if the manager
  /// authenticated, false if biometrics are unavailable, not enrolled, or the
  /// scan was cancelled/failed. Never throws.
  static Future<bool> tryBiometric(String reason) async {
    try {
      final supported =
          await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;
      if (!supported) return false;
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false; // no hardware / not enrolled / locked out -> fall back to PIN
    } catch (_) {
      return false;
    }
  }

  /// Approve [reason]: fingerprint first, PIN fallback. Returns true if approved
  /// (or if the gate is disabled). Never throws.
  static Future<bool> requireManagerApproval(
    BuildContext context, {
    required String reason,
  }) async {
    if (!isEnabled) return true;
    if (await tryBiometric(reason)) return true;
    if (!context.mounted) return false;
    final controller = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            void submit() {
              if (verifyPin(controller.text.trim())) {
                Navigator.pop(dialogContext, true);
              } else {
                setState(() => error = 'Incorrect manager PIN.');
              }
            }

            return AlertDialog(
              title: const Text('Manager approval'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(reason),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Manager PIN',
                      errorText: error,
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(onPressed: submit, child: const Text('Approve')),
              ],
            );
          },
        );
      },
    );
    return approved ?? false;
  }
}
