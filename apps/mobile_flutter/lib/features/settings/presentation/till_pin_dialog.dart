import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/mobile_session_controller.dart';

/// Set or change the 4-digit PIN that identifies whoever is standing at the
/// till. Not the app lock — that is Security, and saying so here stops the
/// support call that used to follow.
///
/// Lifted out of `settings_screen.dart` unchanged during the UI rebuild, to
/// keep that screen under the 400-line ceiling.
Future<void> showTillPinDialog(BuildContext context, WidgetRef ref) async {
  // Asking for a "current PIN" that was never set made this impossible to use.
  final hasPin = await ref.read(mobileSessionProvider.notifier).hasStaffPin();
  if (!context.mounted) return;

  final current = TextEditingController();
  final next = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(hasPin ? 'Change till PIN' : 'Set till PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            hasPin
                ? 'This PIN identifies you on the till. It is not the app '
                      'lock — that lives in Settings > Security.'
                : 'You have not set a till PIN yet. Choose one now.',
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          if (hasPin)
            TextField(
              controller: current,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'Current PIN',
                counterText: '',
              ),
            ),
          TextField(
            controller: next,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: 'New PIN',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    if (next.text.trim().length < 4) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New PIN must be 4 digits.')),
        );
      }
    } else {
      final changed = await ref
          .read(mobileSessionProvider.notifier)
          .changePin(current.text.trim(), next.text.trim());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              changed
                  ? (hasPin ? 'Till PIN updated.' : 'Till PIN set.')
                  : 'Current PIN is incorrect.',
            ),
          ),
        );
      }
    }
  }
  current.dispose();
  next.dispose();
}
