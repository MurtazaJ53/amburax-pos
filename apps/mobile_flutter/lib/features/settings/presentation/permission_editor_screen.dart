import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_api_client.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../ui/ui.dart';

/// Role & permission editor for a single workspace member. Fetches the module
/// x action catalog from the backend, renders a toggle matrix seeded with the
/// member's current permissions, and saves role + custom permissions.
/// Responsive: single-column cards on phone, wider grid on tablet.
class PermissionEditorScreen extends ConsumerStatefulWidget {
  const PermissionEditorScreen({super.key, required this.member});

  final WorkspaceTeamMemberRecord member;

  @override
  ConsumerState<PermissionEditorScreen> createState() =>
      _PermissionEditorScreenState();
}

class _PermissionEditorScreenState
    extends ConsumerState<PermissionEditorScreen> {
  List<Map<String, dynamic>> _catalog = const [];
  Map<String, String> _actionLabels = const {};
  // module -> action -> enabled
  final Map<String, Map<String, bool>> _perms = {};
  late String _role;
  String _search = '';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  static const _assignableRoles = <(String, String)>[
    ('admin', 'Admin'),
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
  void initState() {
    super.initState();
    _role = widget.member.role;
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || (session.shopId ?? '').isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No active shop.';
      });
      return;
    }
    try {
      final client = ref.read(backendApiClientProvider);
      final data = await client.getPermissionCatalog(
        user: session.user,
        shopId: session.shopId!,
      );
      final catalog = (data['catalog'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final labels = (data['action_labels'] as Map? ?? const {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      );
      // Seed toggles from the member's current permissions.
      final current = widget.member.permissions;
      for (final module in catalog) {
        final mk = module['key'].toString();
        final actions = (module['actions'] as List? ?? const [])
            .map((a) => a.toString())
            .toList();
        final existing = current[mk];
        _perms[mk] = {
          for (final a in actions)
            a: existing is Map ? existing[a] == true : false,
        };
      }
      setState(() {
        _catalog = catalog;
        _actionLabels = labels;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Could not load permissions. $e';
      });
    }
  }

  Map<String, dynamic> _buildPermissionsJson() {
    final out = <String, dynamic>{};
    _perms.forEach((module, actions) {
      final on = <String, bool>{
        for (final e in actions.entries)
          if (e.value) e.key: true,
      };
      if (on.isNotEmpty) out[module] = on;
    });
    return out;
  }

  Future<void> _save() async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(backendApiClientProvider)
          .updateWorkspaceTeamMember(
            user: session.user,
            shopId: session.shopId!,
            membershipId: widget.member.id,
            role: _role,
            permissions: _buildPermissionsJson(),
          );
      ref.invalidate(workspaceTeamMembersProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved permissions for ${widget.member.memberName}.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  void _resetAll() {
    setState(() {
      for (final actions in _perms.values) {
        for (final k in actions.keys.toList()) {
          actions[k] = false;
        }
      }
    });
  }

  Future<void> _export() async {
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(_buildPermissionsJson());
    await Clipboard.setData(ClipboardData(text: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission set copied to clipboard.')),
      );
    }
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const FormatException('not an object');
      setState(() {
        for (final module in _perms.keys) {
          final incoming = decoded[module];
          for (final action in _perms[module]!.keys.toList()) {
            _perms[module]![action] =
                incoming is Map && incoming[action] == true;
          }
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permission set imported from clipboard.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Clipboard did not contain a valid permission set.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final visibleModules = _catalog.where((m) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return m['label'].toString().toLowerCase().contains(q) ||
          m['key'].toString().toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Permissions · ${widget.member.memberName}'),
        actions: [
          if (!_loading && _error == null)
            IconButton(
              tooltip: 'Save',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              children: [
                AppPanel(
                  title: 'Role',
                  child: DropdownButtonFormField<String>(
                    initialValue: _assignableRoles.any((r) => r.$1 == _role)
                        ? _role
                        : null,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: _assignableRoles
                        .map(
                          (r) =>
                              DropdownMenuItem(value: r.$1, child: Text(r.$2)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _role = v ?? _role),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Search modules…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                    filled: true,
                    fillColor: colors.backgroundSoft,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _resetAll,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Clear all'),
                    ),
                    TextButton.icon(
                      onPressed: _export,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Export'),
                    ),
                    TextButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.paste_rounded, size: 18),
                      label: const Text('Import'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final module in visibleModules) _moduleCard(module),
              ],
            ),
    );
  }

  Widget _moduleCard(Map<String, dynamic> module) {
    final mk = module['key'].toString();
    final actions = (module['actions'] as List? ?? const [])
        .map((a) => a.toString())
        .toList();
    final state = _perms[mk] ?? {};
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppPanel(
        title: module['label'].toString(),
        action: AppTag(
          label: '${state.values.where((v) => v).length}/${actions.length}',
          icon: Icons.tune_rounded,
          tone: AppTone.info,
        ),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final a in actions)
              FilterChip(
                label: Text(_actionLabels[a] ?? a),
                selected: state[a] ?? false,
                onSelected: (sel) => setState(() => _perms[mk]![a] = sel),
              ),
          ],
        ),
      ),
    );
  }
}
