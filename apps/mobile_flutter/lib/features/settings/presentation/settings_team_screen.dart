import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/models/mobile_session.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/runtime/mobile_runtime_config.dart';
import '../../../core/session/mobile_session_controller.dart';
import 'invite_share_sheet.dart';
import 'permission_editor_screen.dart';
import '../../../ui/ui.dart';

class SettingsTeamScreen extends ConsumerWidget {
  const SettingsTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(mobileSessionProvider).asData?.value;
    final shop =
        ref.watch(shopInfoProvider).asData?.value ?? ShopInfo.fallback();
    final membersAsync = ref.watch(workspaceTeamMembersProvider);
    final members =
        membersAsync.asData?.value ?? const <WorkspaceTeamMemberRecord>[];

    if (session == null) {
      return AppScreen(
        scrollable: false,
        title: 'Workspace team',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            AppPanel(
              title: 'Loading workspace team',
              child: AppEmptyState(
                icon: Icons.sync_rounded,
                title: 'Checking access',
                body:
                    'Business Hub is loading the signed-in workspace before opening team controls.',
              ),
            ),
          ],
        ),
      );
    }

    if (!session.isOwnerLike) {
      return AppScreen(
        scrollable: false,
        title: 'Workspace team',
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
          children: const <Widget>[
            AppPanel(
              title: 'Owner/admin only',
              child: AppEmptyState(
                icon: Icons.lock_outline_rounded,
                title: 'Team control stays elevated',
                body:
                    'Daily operators should stay focused on selling and stock work. Team role control stays limited to workspace owners and admins.',
              ),
            ),
          ],
        ),
      );
    }

    return AppScreen(
      scrollable: false,
      title: 'Workspace team',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          AppScreenLead(
            title: 'Connect staff to ${shop.name}',
            subtitle:
                'Add the exact email a staff member will use to sign in. Business Hub will attach that person to this workspace and keep role control with owner/admin users.',
            tags: <Widget>[
              AppTag(
                label: shop.planLabel,
                icon: Icons.workspace_premium_rounded,
                tone: AppTone.warning,
              ),
              AppTag(
                label: session.displayRoleLabel,
                icon: Icons.badge_rounded,
                tone: AppTone.success,
              ),
            ],
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'How staff joins',
            action: const AppTag(
              label: 'SIGN-IN FLOW',
              icon: Icons.login_rounded,
              tone: AppTone.success,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _TeamBullet(
                  text:
                      'Add the staff member with the same email they will use on the phone.',
                ),
                _TeamBullet(
                  text:
                      'After that, the staff member opens the app and signs in with that email.',
                ),
                _TeamBullet(
                  text:
                      'If it is their first time, they can use password recovery to set or reset their password before signing in.',
                ),
              ],
            ),
          ),
          if (MobileRuntimeConfig.backendAuthMode == 'jwt') ...<Widget>[
            const SizedBox(height: 18),
            const _CloudInvitePanel(),
          ],
          const SizedBox(height: 18),
          AppPanel(
            title: 'Team roster',
            action: AppTag(
              label: members.isEmpty
                  ? (membersAsync.isLoading ? 'Refreshing' : 'No members')
                  : '${members.length} attached',
              icon: Icons.groups_rounded,
              tone: AppTone.primary,
            ),
            child: members.isEmpty
                ? AppEmptyState(
                    icon: membersAsync.isLoading
                        ? Icons.sync_rounded
                        : Icons.group_off_rounded,
                    title: membersAsync.isLoading
                        ? 'Refreshing workspace team'
                        : 'No attached members yet',
                    body: membersAsync.isLoading
                        ? 'Business Hub is loading the current workspace roster.'
                        : 'Attach staff, viewers, or another store admin so they can sign in with the same email and access this shop.',
                  )
                : Column(
                    children: members
                        .map(
                          (member) => _TeamMemberRow(
                            member: member,
                            onManage: member.canManage
                                ? () => _openManageMemberSheet(
                                    context: context,
                                    ref: ref,
                                    session: session,
                                    member: member,
                                  )
                                : null,
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'Add member',
            action: const AppTag(
              label: 'OWNER / ADMIN',
              icon: Icons.person_add_alt_1_rounded,
              tone: AppTone.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Invite a daily operator, store admin, or read-only reviewer into this workspace.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.black.withValues(alpha: 0.72),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () {
                    if (!MobileRuntimeConfig.backendSyncEnabled) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Staff invites need backend sync. Local mode currently keeps only the owner session active.',
                          ),
                        ),
                      );
                      return;
                    }
                    _openAddMemberSheet(
                      context: context,
                      ref: ref,
                      session: session,
                      shopName: shop.name,
                    );
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add workspace member'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddMemberSheet({
    required BuildContext context,
    required WidgetRef ref,
    required MobileSession session,
    required String shopName,
  }) async {
    final colors = AppColors.of(context);
    if (!session.hasShop) {
      return;
    }
    final emailController = TextEditingController();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedRole = 'staff';
    bool saving = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final roleChoices = session.isOwner
                ? const <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Store admin'),
                    ),
                    DropdownMenuItem(
                      value: 'staff',
                      child: Text('Staff operator'),
                    ),
                    DropdownMenuItem(
                      value: 'viewer',
                      child: Text('Read-only viewer'),
                    ),
                  ]
                : const <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                      value: 'staff',
                      child: Text('Staff operator'),
                    ),
                    DropdownMenuItem(
                      value: 'viewer',
                      child: Text('Read-only viewer'),
                    ),
                  ];

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    const AppSheetHeader(
                      eyebrow: 'Workspace team',
                      title: 'Add member',
                      subtitle:
                          'Attach a person to this shop so they can sign in with the same email on mobile.',
                      icon: Icons.person_add_alt_1_rounded,
                    ),
                    const SizedBox(height: 16),
                    AppPanel(
                      title: 'Member details',
                      child: Column(
                        children: <Widget>[
                          TextField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'operator@example.com',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            textCapitalization: TextCapitalization.sentences,
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              hintText: 'Floor Operator',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Phone',
                              hintText: '+91-9999999999',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: selectedRole,
                            items: roleChoices,
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                selectedRole = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Role',
                            ),
                          ),
                          if (errorText != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              errorText!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppPalette.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      if (emailController.text.trim().isEmpty) {
                                        setState(() {
                                          errorText = 'Email is required.';
                                        });
                                        return;
                                      }
                                      setState(() {
                                        saving = true;
                                        errorText = null;
                                      });
                                      try {
                                        final record = await ref
                                            .read(backendApiClientProvider)
                                            .createWorkspaceTeamMember(
                                              user: session.user,
                                              shopId: session.shopId!,
                                              email: emailController.text
                                                  .trim(),
                                              fullName: nameController.text
                                                  .trim(),
                                              phone: phoneController.text
                                                  .trim(),
                                              role: selectedRole,
                                            );
                                        ref.invalidate(
                                          workspaceTeamMembersProvider,
                                        );
                                        if (!context.mounted) {
                                          return;
                                        }
                                        Navigator.of(context).pop();
                                        // New member -> show the shareable
                                        // QR / code so they can sign in.
                                        // Otherwise just confirm the update.
                                        if (record.hasInvite) {
                                          await showInviteShareSheet(
                                            context,
                                            record: record,
                                            shopName: shopName,
                                          );
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Workspace member updated.',
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (error) {
                                        setState(() {
                                          errorText = error.toString();
                                          saving = false;
                                        });
                                      }
                                    },
                              icon: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded),
                              label: Text(
                                saving ? 'Saving member' : 'Save member',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openManageMemberSheet({
    required BuildContext context,
    required WidgetRef ref,
    required MobileSession session,
    required WorkspaceTeamMemberRecord member,
  }) async {
    final colors = AppColors.of(context);
    if (!session.hasShop) {
      return;
    }
    if (!MobileRuntimeConfig.backendSyncEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Role changes need backend sync. Local mode keeps the owner session active.',
          ),
        ),
      );
      return;
    }

    String selectedRole = member.role;
    String selectedStatus = member.status;
    bool saving = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.background,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final roleChoices = session.isOwner
                ? const <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Store admin'),
                    ),
                    DropdownMenuItem(
                      value: 'staff',
                      child: Text('Staff operator'),
                    ),
                    DropdownMenuItem(
                      value: 'viewer',
                      child: Text('Read-only viewer'),
                    ),
                  ]
                : const <DropdownMenuItem<String>>[
                    DropdownMenuItem(
                      value: 'staff',
                      child: Text('Staff operator'),
                    ),
                    DropdownMenuItem(
                      value: 'viewer',
                      child: Text('Read-only viewer'),
                    ),
                  ];

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  18,
                  18,
                  24 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    AppSheetHeader(
                      eyebrow: 'Workspace team',
                      title: member.memberName,
                      subtitle: member.memberEmail,
                      icon: Icons.manage_accounts_rounded,
                      tags: <Widget>[
                        AppTag(
                          label: member.roleLabel,
                          icon: Icons.badge_rounded,
                          tone: AppTone.primary,
                        ),
                        AppTag(
                          label: member.status,
                          icon: Icons.circle_notifications_rounded,
                          tone: AppTone.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppPanel(
                      title: 'Role and access',
                      child: Column(
                        children: <Widget>[
                          DropdownButtonFormField<String>(
                            initialValue: selectedRole,
                            items: roleChoices,
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                selectedRole = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Role',
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: selectedStatus,
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem(
                                value: 'active',
                                child: Text('Active'),
                              ),
                              DropdownMenuItem(
                                value: 'invited',
                                child: Text('Invited'),
                              ),
                              DropdownMenuItem(
                                value: 'disabled',
                                child: Text('Disabled'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                selectedStatus = value;
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                          ),
                          if (errorText != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Text(
                              errorText!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppPalette.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.tonalIcon(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      setState(() {
                                        saving = true;
                                        errorText = null;
                                      });
                                      try {
                                        await ref
                                            .read(backendApiClientProvider)
                                            .updateWorkspaceTeamMember(
                                              user: session.user,
                                              shopId: session.shopId!,
                                              membershipId: member.id,
                                              role: selectedRole,
                                              status: selectedStatus,
                                            );
                                        ref.invalidate(
                                          workspaceTeamMembersProvider,
                                        );
                                        if (!context.mounted) {
                                          return;
                                        }
                                        Navigator.of(context).pop();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Workspace member updated.',
                                            ),
                                          ),
                                        );
                                      } catch (error) {
                                        setState(() {
                                          saving = false;
                                          errorText = error.toString();
                                        });
                                      }
                                    },
                              icon: saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_rounded),
                              label: Text(
                                saving ? 'Saving changes' : 'Save changes',
                              ),
                            ),
                          ),
                          if (MobileRuntimeConfig.backendAuthMode == 'jwt') ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PermissionEditorScreen(
                                        member: member,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.tune_rounded),
                                label: const Text('Manage permissions'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TeamMemberRow extends StatelessWidget {
  const _TeamMemberRow({required this.member, this.onManage});

  final WorkspaceTeamMemberRecord member;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceStrong,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      member.memberName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (onManage != null)
                    FilledButton.tonal(
                      onPressed: onManage,
                      child: const Text('Manage'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                member.memberEmail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  AppTag(
                    label: member.roleLabel,
                    icon: Icons.badge_rounded,
                    tone: AppTone.primary,
                  ),
                  AppTag(
                    label: member.status,
                    icon: Icons.circle_notifications_rounded,
                    tone: AppTone.warning,
                  ),
                  if (member.isCurrentUser)
                    const AppTag(
                      label: 'YOU',
                      icon: Icons.person_rounded,
                      tone: AppTone.success,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                member.roleSummary,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black.withValues(alpha: 0.68),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamBullet extends StatelessWidget {
  const _TeamBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppPalette.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.black.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cloud invitation panel (JWT mode): invite a teammate by email + role.
/// The backend emails them an invite code; the code is also shown here so the
/// owner can share it directly (WhatsApp/SMS) if needed.
class _CloudInvitePanel extends ConsumerStatefulWidget {
  const _CloudInvitePanel();

  @override
  ConsumerState<_CloudInvitePanel> createState() => _CloudInvitePanelState();
}

class _CloudInvitePanelState extends ConsumerState<_CloudInvitePanel> {
  final _emailController = TextEditingController();
  String _role = 'cashier';
  bool _sending = false;
  String? _lastCode;

  static const _roles = <(String, String)>[
    ('manager', 'Manager'),
    ('supervisor', 'Supervisor'),
    ('accountant', 'Accountant'),
    ('hr', 'HR'),
    ('cashier', 'Cashier'),
    ('sales_staff', 'Sales Staff'),
    ('inventory_staff', 'Inventory Staff'),
    ('viewer', 'Viewer'),
  ];

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }
    setState(() => _sending = true);
    final result = await ref
        .read(mobileSessionProvider.notifier)
        .sendInvite(email: email, role: _role);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _lastCode = result.code;
    });
    if (result.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error!)));
    } else {
      _emailController.clear();
      // Honest feedback: distinguish "email delivered" from "invite created
      // but email couldn't be delivered" (e.g. Resend not domain-verified).
      final msg = result.emailSent
          ? 'Invite emailed to $email.'
          : 'Invite created. Email not delivered'
                '${result.emailError.isNotEmpty ? ' (${result.emailError})' : ''} '
                '- share the code below instead.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 6)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppPanel(
      title: 'Invite a teammate',
      action: const AppTag(
        label: 'CLOUD',
        icon: Icons.group_add_rounded,
        tone: AppTone.info,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'They get an email with a code. In the app they choose '
            '"Join with a code" to set a password and join your shop.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Teammate email',
              isDense: true,
              filled: true,
              fillColor: colors.backgroundSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _role,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Role',
                    isDense: true,
                    filled: true,
                    fillColor: colors.backgroundSoft,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: _roles
                      .map(
                        (r) => DropdownMenuItem(value: r.$1, child: Text(r.$2)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _role = v ?? 'cashier'),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _sending ? null : _send,
                  style: ElevatedButton.styleFrom(),
                  child: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: AppPalette.primaryDark,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Invite'),
                ),
              ),
            ],
          ),
          if (_lastCode != null && _lastCode!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Share this code directly if needed:',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _lastCode!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
