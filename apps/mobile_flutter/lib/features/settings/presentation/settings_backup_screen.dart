import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../ui/ui.dart';

class SettingsBackupScreen extends ConsumerStatefulWidget {
  const SettingsBackupScreen({super.key});

  @override
  ConsumerState<SettingsBackupScreen> createState() =>
      _SettingsBackupScreenState();
}

class _SettingsBackupScreenState extends ConsumerState<SettingsBackupScreen> {
  List<File> _backups = const <File>[];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final backups = await ref.read(backupServiceProvider).listBackups();
    if (!mounted) return;
    setState(() {
      _backups = backups;
      _loading = false;
    });
  }

  Future<void> _createBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await ref.read(backupServiceProvider).createBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup saved: ${_name(file)}')));
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(
    String label,
    Future<File> Function(BackupService service) run,
  ) async {
    try {
      final file = await run(ref.read(backupServiceProvider));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label exported: ${_name(file)}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label export failed: $error')));
    }
  }

  Future<void> _restore(File backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: const Text(
          'This replaces ALL current data with the backup. The app will close '
          'afterwards — reopen it to finish. This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.error),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(backupServiceProvider).restoreBackup(backup);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Backup restored'),
          content: const Text(
            'Your data has been restored. The app will now close — please '
            'reopen it.',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Close app'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
    }
  }

  Future<void> _delete(File backup) async {
    await ref.read(backupServiceProvider).deleteBackup(backup);
    await _refresh();
  }

  String _name(File f) => f.uri.pathSegments.last;

  String _size(File f) {
    final bytes = f.lengthSync();
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppScreen(
      scrollable: false,
      title: L.of(context).backupTitle,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          AppPanel(
            title: 'Backup',
            action: const AppTag(
              label: 'ON THIS DEVICE',
              icon: Icons.save_rounded,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Save a full copy of your sales, inventory, customers and '
                  'dues. Keep a recent backup so you never lose your books if '
                  'the phone is lost or reset.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _createBackup,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppPalette.primaryDark,
                            ),
                          )
                        : const Icon(Icons.backup_rounded),
                    label: Text(_busy ? 'Backing up...' : 'Create backup now'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: L.of(context).backupSaved,
            action: AppTag(
              label: '${_backups.length}',
              icon: Icons.folder_rounded,
            ),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _backups.isEmpty
                ? const AppEmptyState(
                    icon: Icons.inbox_rounded,
                    title: 'No backups yet',
                    body: 'Tap "Create backup now" to make your first one.',
                  )
                : Column(
                    children: _backups
                        .map(
                          (f) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colors.borderSoft),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.description_rounded,
                                color: AppPalette.primary,
                              ),
                              title: Text(
                                _name(f),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(_size(f)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  IconButton(
                                    icon: const Icon(Icons.restore_rounded),
                                    color: AppPalette.primary,
                                    tooltip: 'Restore',
                                    onPressed: () => _restore(f),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    color: AppPalette.error,
                                    tooltip: 'Delete',
                                    onPressed: () => _delete(f),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
          const SizedBox(height: 18),
          AppPanel(
            title: 'Export to CSV',
            action: const AppTag(
              label: 'FOR EXCEL',
              icon: Icons.table_chart_rounded,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Export your data as spreadsheet files you can open in Excel '
                  'or Google Sheets, or send to your accountant.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    _ExportChip(
                      label: 'Sales',
                      icon: Icons.receipt_long_rounded,
                      onTap: () => _export('Sales', (s) => s.exportSalesCsv()),
                    ),
                    _ExportChip(
                      label: 'Inventory',
                      icon: Icons.inventory_2_rounded,
                      onTap: () =>
                          _export('Inventory', (s) => s.exportInventoryCsv()),
                    ),
                    _ExportChip(
                      label: 'Customers',
                      icon: Icons.groups_rounded,
                      onTap: () =>
                          _export('Customers', (s) => s.exportCustomersCsv()),
                    ),
                    _ExportChip(
                      label: 'GST (B2B)',
                      icon: Icons.request_quote_rounded,
                      onTap: () =>
                          _export('GSTR-1 B2B', (s) => s.exportGstr1Csv()),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Backups and exports are stored on this device (in business-hub-'
            'backups / business-hub-exports). Copy them to Google Drive or a '
            'computer for off-device safety.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _ExportChip extends StatelessWidget {
  const _ExportChip({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: AppPalette.primary),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
