import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/mobile_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/whatsapp.dart';
import '../../pos/presentation/upi_qr_view.dart';

/// Shows the shareable invite for a freshly added member: a QR of the invite
/// deep link, the short code, and quick ways to hand it over (WhatsApp / copy).
///
/// The invitee joins by scanning the QR from the sign-in screen, tapping the
/// link, or typing the code — all three carry the same single-use token.
Future<void> showInviteShareSheet(
  BuildContext context, {
  required WorkspaceTeamMemberRecord record,
  String shopName = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InviteShareSheet(record: record, shopName: shopName),
  );
}

class _InviteShareSheet extends StatelessWidget {
  const _InviteShareSheet({required this.record, required this.shopName});

  final WorkspaceTeamMemberRecord record;
  final String shopName;

  String get _message {
    final where = shopName.isEmpty ? 'our shop' : shopName;
    return "You've been added to $where on Business Hub as "
        '${record.roleLabel}.\n\n'
        'To sign in: open the Business Hub app → "Have an invite? Scan" and '
        'scan the QR, or enter this code:\n\n${record.inviteCode}\n\n'
        'Or tap: ${record.inviteLink}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppPalette.success.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppPalette.success,
                  size: 30,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '${record.memberName} added',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Share this invite so they can sign in as ${record.roleLabel}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 22),

              // Scannable QR of the invite deep link.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.borderSoft),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: UpiQrView(data: record.inviteLink, size: 208),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // The short code, big and copyable.
              _CodeChip(code: record.inviteCode, colors: colors),
              const SizedBox(height: 20),

              if (record.phone.trim().isNotEmpty) ...<Widget>[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _sendWhatsApp(context),
                    icon: const Icon(Icons.chat_rounded),
                    label: const Text('Send on WhatsApp'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(context, record.inviteCode, 'Code'),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy code'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copy(context, _message, 'Invite'),
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: const Text('Copy invite'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendWhatsApp(BuildContext context) async {
    final ok = await openWhatsApp(phone: record.phone, message: _message);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp for that number.'),
        ),
      );
    }
  }

  Future<void> _copy(BuildContext context, String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard.')),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, required this.colors});

  final String code;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'INVITE CODE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            code,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
