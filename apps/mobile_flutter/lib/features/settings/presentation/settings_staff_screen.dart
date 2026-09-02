import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../ui/ui.dart';

const List<String> _roles = <String>['owner', 'manager', 'staff'];

String _roleLabel(String role) {
  switch (role) {
    case 'owner':
      return 'Owner';
    case 'manager':
      return 'Manager';
    default:
      return 'Staff';
  }
}

/// Manage staff accounts — each has a name, role, and personal PIN.
class SettingsStaffScreen extends ConsumerStatefulWidget {
  const SettingsStaffScreen({super.key});

  @override
  ConsumerState<SettingsStaffScreen> createState() =>
      _SettingsStaffScreenState();
}

class _SettingsStaffScreenState extends ConsumerState<SettingsStaffScreen> {
  List<StaffUser> _staff = const <StaffUser>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final staff = await ref.read(mobileSessionProvider.notifier).listStaff();
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _loading = false;
    });
  }

  Future<void> _addStaff() async {
    final nameController = TextEditingController();
    final pinController = TextEditingController();
    var role = 'staff';
    final added = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          title: const Text('Add staff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: _roles
                    .map(
                      (r) => DropdownMenuItem<String>(
                        value: r,
                        child: Text(_roleLabel(r)),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setD(() => role = v ?? 'staff'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(
                  labelText: 'PIN (4 digits)',
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
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (added == true) {
      final error = await ref
          .read(mobileSessionProvider.notifier)
          .addStaff(
            name: nameController.text,
            role: role,
            pin: pinController.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error ?? 'Staff added.')));
      }
      await _refresh();
    }
    nameController.dispose();
    pinController.dispose();
  }

  Future<void> _remove(StaffUser s) async {
    if (s.role == 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The owner account cannot be removed.')),
      );
      return;
    }
    await ref.read(mobileSessionProvider.notifier).removeStaff(s.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppScreen(
      scrollable: false,
      title: 'Staff & PINs',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          AppPanel(
            title: 'Staff accounts',
            action: AppTag(
              label: '${_staff.length}',
              icon: Icons.groups_rounded,
              tone: AppTone.primary,
            ),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    children: <Widget>[
                      for (final s in _staff) ...<Widget>[
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colors.borderSoft),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppPalette.primary.withValues(
                                alpha: 0.12,
                              ),
                              child: Text(
                                s.name.isEmpty ? '?' : s.name[0].toUpperCase(),
                                style: const TextStyle(
                                  color: AppPalette.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            title: Text(
                              s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(_roleLabel(s.role)),
                            trailing: s.role == 'owner'
                                ? const Chip(label: Text('Owner'))
                                : IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    color: AppPalette.error,
                                    onPressed: () => _remove(s),
                                  ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _addStaff,
                          icon: const Icon(Icons.person_add_rounded),
                          label: const Text('Add staff'),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            'Each person signs in with their own PIN. Owners and managers get '
            'full control; staff run the till (no cost/profit, no deletes or '
            'refunds).',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
