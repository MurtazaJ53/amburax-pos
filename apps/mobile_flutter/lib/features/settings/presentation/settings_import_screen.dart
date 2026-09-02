import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/import/date_parse.dart';
import '../../../core/import/universal_import.dart';
import '../../../core/import/xlsx_reader.dart' show looksLikeXlsx;
import '../../../core/import/universal_import_service.dart';
import '../../../core/backend/backend_api_client.dart';
import '../../../core/database/mobile_repository.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/import/zobaze_import.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import 'universal_import_sheet.dart';
import '../../../ui/ui.dart';

/// Migrate data in from another POS (currently Zobaze .xlsx exports).
class SettingsImportScreen extends ConsumerStatefulWidget {
  const SettingsImportScreen({super.key});

  @override
  ConsumerState<SettingsImportScreen> createState() =>
      _SettingsImportScreenState();
}

class _SettingsImportScreenState extends ConsumerState<SettingsImportScreen> {
  bool _busy = false;
  ZobazeImportResult? _result;
  String? _error;
  String? _successText;

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _successText = null;
    });
    try {
      final service = ref.read(zobazeImportServiceProvider);
      final file = await service.pickFile();
      if (file == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final result = await service.importFile(file);
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    }
  }

  /// Pick a CSV/XLSX file of any layout, auto-map its columns, let the user
  /// confirm, then import via the universal engine.
  static String _labelFor(ImportKind k) => switch (k) {
    ImportKind.products => 'products',
    ImportKind.customers => 'customers',
    ImportKind.sales => 'sales',
    ImportKind.expenses => 'expenses',
    ImportKind.suppliers => 'suppliers',
  };

  void _startBusy() => setState(() {
    _busy = true;
    _error = null;
    _result = null;
    _successText = null;
  });

  /// Pick a CSV/XLSX and parse it. Returns null (resetting busy) on cancel; throws
  /// with a clean message on an unreadable file.
  Future<ParsedTable?> _pickTable() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['csv', 'xlsx', 'xls'],
    );
    final path = picked?.files.single.path;
    if (path == null) {
      if (mounted) setState(() => _busy = false);
      return null;
    }
    final file = File(path);
    ParsedTable? table;
    // Parse in a background isolate — a large (e.g. 27 MB) file would otherwise
    // block the UI thread for seconds and trigger an Android "app isn't
    // responding" warning.
    if (path.toLowerCase().endsWith('.csv')) {
      final content = await file.readAsString();
      table = await compute(parseCsv, content);
    } else {
      final bytes = await file.readAsBytes();
      if (!looksLikeXlsx(bytes)) {
        // Legacy .xls (BIFF) isn't a zip and can't be read by any reader here.
        throw Exception(
          'This is an old .xls file. Open it in Excel/Google Sheets and save it '
          'as .xlsx (or .csv), then import again.',
        );
      }
      table = await compute(parseXlsxBytes, bytes);
    }
    if (table == null) {
      throw Exception(
        "Couldn't read this spreadsheet. Please re-save it as .csv and try again.",
      );
    }
    if (table.headers.isEmpty || table.rows.isEmpty) {
      throw Exception('No rows found. The first line must be column headers.');
    }
    return table;
  }

  /// Show the mapping preview for [kind] + [table] and write the confirmed rows.
  Future<void> _runImport(ImportKind kind, ParsedTable table) async {
    final label = _labelFor(kind);
    if (!mounted) return;
    final mapping = await showMappingSheet(
      context,
      table: table,
      kind: kind,
      title: 'Import $label',
    );
    if (mapping == null) {
      if (mounted) setState(() => _busy = false);
      return; // cancelled
    }
    final mapped = await compute(_mapRowsIsolate, (table, kind, mapping));
    final service = ref.read(universalImportServiceProvider);
    // Products & customers push each row to the server (so imports persist just
    // like manual adds) with a live progress dialog. Sales/expenses stay local
    // history imports.
    final outcome = switch (kind) {
      ImportKind.products => await _pushImport(kind, mapped),
      ImportKind.customers => await _pushImport(kind, mapped),
      ImportKind.sales => await _pushSalesImport(mapped),
      ImportKind.expenses => await service.importExpenses(mapped),
      ImportKind.suppliers => throw Exception(
        'Suppliers import is not available yet.',
      ),
    };
    if (!mounted) return;
    setState(() {
      _busy = false;
      _successText =
          '${outcome.imported} $label imported'
          '${outcome.skipped > 0 ? ' (${outcome.skipped} skipped)' : ''}.'
          // Say it plainly when dates could not be read - these rows got
          // stamped with today, and the owner needs to know their history
          // was re-dated rather than find out from a wrong report later.
          '${outcome.undatedRows > 0 ? ' ${outcome.undatedRows} had an unreadable date and were set to today.' : ''}'
          // Tell them the file was already imported. Without this, a repeat
          // import looks identical to a fresh one and the only way to find out
          // is to go hunting through History.
          '${outcome.replacedRows > 0 ? ' ${outcome.replacedRows} already existed and were updated, not duplicated.' : ''}';
    });
  }

  /// Import products/customers by pushing each row to the server (so they
  /// persist like manual adds), showing a live progress bar. Each network call
  /// yields the UI thread, so the bar animates instead of freezing.
  Future<ImportOutcome> _pushImport(
    ImportKind kind,
    MappedImport mapped,
  ) async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) {
      throw Exception('Sign in to a shop before importing.');
    }
    final api = ref.read(backendApiClientProvider);
    final rows = mapped.rows;
    final total = rows.length;
    final progress = ValueNotifier<int>(0);
    var created = 0;
    var skipped = 0;
    const batchSize = 200;

    if (mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              _ImportProgressDialog(total: total, progress: progress),
        ),
      );
    }
    try {
      for (var start = 0; start < rows.length; start += batchSize) {
        final end = (start + batchSize) > rows.length
            ? rows.length
            : start + batchSize;
        final payload = <Map<String, dynamic>>[];
        for (final row in rows.sublist(start, end)) {
          final name = (row['name'] ?? '').trim();
          if (name.isEmpty) {
            skipped++;
            continue;
          }
          if (kind == ImportKind.products) {
            final cost = parseNum(row['costPrice']);
            payload.add(<String, dynamic>{
              'name': name,
              'sell_price': parseNum(row['price']).toStringAsFixed(2),
              'opening_stock': parseNum(row['stock']),
              'sku': (row['sku'] ?? row['barcode'] ?? '').trim(),
              'category': (row['category'] ?? '').trim().isEmpty
                  ? 'General'
                  : row['category']!.trim(),
              'hsn_code': (row['hsnCode'] ?? '').trim(),
              'gst_rate': parseNum(row['gstRate']).toStringAsFixed(2),
              'price_includes_tax': true,
              'status': 'active',
              if (cost > 0) 'private_cost_price': cost.toStringAsFixed(2),
            });
          } else {
            // Opening balance = amount owed minus any advance held. The mapper
            // exposes these as 'amountDue' and 'advance' (NOT 'balance').
            final due = parseNum(row['amountDue']);
            final advance = parseNum(row['advance']);
            payload.add(<String, dynamic>{
              'name': name,
              'phone': (row['phone'] ?? '').trim(),
              'email': (row['email'] ?? '').trim(),
              'notes': (row['notes'] ?? row['address'] ?? '').trim(),
              'opening_balance': (due - advance).toStringAsFixed(2),
            });
          }
        }
        if (payload.isNotEmpty) {
          try {
            final res = kind == ImportKind.products
                ? await api.bulkCreateInventory(
                    user: session.user,
                    shopId: session.shopId!,
                    items: payload,
                  )
                : await api.bulkCreateCustomers(
                    user: session.user,
                    shopId: session.shopId!,
                    customers: payload,
                  );
            created += (res['created'] as num?)?.toInt() ?? 0;
            skipped += (res['skipped'] as num?)?.toInt() ?? 0;
          } catch (_) {
            skipped += payload.length;
          }
        }
        progress.value = end;
      }
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    // Pull the freshly-created server rows into local so they show immediately.
    await ref.read(mobileSyncCoordinatorProvider).refresh();
    return ImportOutcome(imported: created, skipped: skipped);
  }

  /// Import flat historical sales (past bills) to the server so History syncs.
  /// Batched, with the same progress dialog; dates are parsed to YYYY-MM-DD so
  /// the original bill date is preserved.
  Future<ImportOutcome> _pushSalesImport(MappedImport mapped) async {
    final session = ref.read(mobileSessionProvider).asData?.value;
    if (session == null || !session.hasShop) {
      throw Exception('Sign in to a shop before importing.');
    }
    final api = ref.read(backendApiClientProvider);
    final rows = mapped.rows;
    final total = rows.length;
    final progress = ValueNotifier<int>(0);
    var created = 0;
    var skipped = 0;
    const batchSize = 200;

    if (mounted) {
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) =>
              _ImportProgressDialog(total: total, progress: progress),
        ),
      );
    }
    try {
      for (var start = 0; start < rows.length; start += batchSize) {
        final end = (start + batchSize) > rows.length
            ? rows.length
            : start + batchSize;
        final payload = <Map<String, dynamic>>[];
        for (var j = start; j < end; j++) {
          final row = rows[j];
          final amount = parseNum(row['total']);
          if (amount <= 0) {
            skipped++;
            continue;
          }
          final dt = parseImportDate(row['date']);
          final date = dt != null ? dt.toIso8601String().split('T').first : '';
          payload.add(<String, dynamic>{
            'id': 'imp-sale-$j-$date-${amount.toStringAsFixed(2)}',
            'date': date,
            'total': amount.toStringAsFixed(2),
            'discount': parseNum(row['discount']).toStringAsFixed(2),
            'payment_mode': (row['payment'] ?? 'CASH').trim(),
            'customer_name': (row['customerName'] ?? '').trim(),
            'customer_phone': (row['customerPhone'] ?? '').trim(),
            'footer_note': (row['reference'] ?? '').trim(),
          });
        }
        if (payload.isNotEmpty) {
          try {
            final res = await api.bulkImportSalesHistory(
              user: session.user,
              shopId: session.shopId!,
              sales: payload,
            );
            created += (res['created'] as num?)?.toInt() ?? 0;
            skipped += (res['skipped'] as num?)?.toInt() ?? 0;
          } catch (_) {
            skipped += payload.length;
          }
        }
        progress.value = end;
      }
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    await ref.read(mobileSyncCoordinatorProvider).refresh();
    return ImportOutcome(imported: created, skipped: skipped);
  }

  /// Import a specific data type (user picked the icon).
  Future<void> _importUniversal(ImportKind kind) async {
    if (_busy) return;
    _startBusy();
    try {
      final table = await _pickTable();
      if (table == null) return;
      await _runImport(kind, table);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  /// Smart import: pick ANY exported file, auto-detect whether it's products /
  /// customers / sales, then route it (asks only if we can't tell).
  Future<void> _smartImport() async {
    if (_busy) return;
    _startBusy();
    try {
      final table = await _pickTable();
      if (table == null) return;
      var kind = detectKind(table.headers);
      if (kind == null) {
        if (!mounted) return;
        kind = await _chooseKind();
        if (kind == null) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }
      await _runImport(kind, table);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<ImportKind?> _chooseKind() => showDialog<ImportKind>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text("Couldn't auto-detect — what is this file?"),
      children: <Widget>[
        for (final k in detectableKinds)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, k),
            child: Text(
              '${_labelFor(k)[0].toUpperCase()}${_labelFor(k).substring(1)}',
            ),
          ),
      ],
    ),
  );

  /// Import customers straight from the phone's address book (name + first
  /// phone), without saving anything to the device's contacts.
  Future<void> _importContacts() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _successText = null;
    });
    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        throw Exception(
          'Contacts permission denied. Enable it in Settings to import.',
        );
      }
      final contacts = await FlutterContacts.getAll(
        properties: <ContactProperty>{
          ContactProperty.name,
          ContactProperty.phone,
        },
      );
      final rows = <Map<String, String>>[];
      for (final c in contacts) {
        final name = (c.displayName ?? '').trim();
        final phone = c.phones.isNotEmpty ? c.phones.first.number.trim() : '';
        if (name.isEmpty && phone.isEmpty) continue;
        rows.add(<String, String>{
          'name': name.isEmpty ? phone : name,
          'phone': phone,
        });
      }
      if (rows.isEmpty) {
        throw Exception('No contacts with a name or phone were found.');
      }
      final service = ref.read(universalImportServiceProvider);
      final outcome = await service.importCustomers(
        MappedImport(
          rows,
          const <String>[],
          ColumnMapping(const <String>[], const <String, int>{}),
        ),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _successText =
            '${outcome.imported} customer(s) imported from contacts.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Save CSV text to a user-chosen location; returns a status message.
  Future<void> _saveCsv(String content, String fileName) async {
    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: <String>['csv'],
      bytes: utf8.encode(content),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (path != null) _successText = 'Saved $fileName.';
    });
  }

  Future<void> _downloadTemplate(ImportKind kind, String label) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _successText = null;
    });
    try {
      await _saveCsv(templateCsvFor(kind), '${label}_template.csv');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _exportCsv(ImportKind kind, String label) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _successText = null;
    });
    try {
      final service = ref.read(universalImportServiceProvider);
      final csv = kind == ImportKind.products
          ? await service.exportProductsCsv()
          : await service.exportCustomersCsv();
      await _saveCsv(csv, '${label}_export.csv');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppScreen(
      scrollable: false,
      title: 'Import data',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          // 1) Smart import — auto-detect the type from ANY exported file.
          _SmartImportCard(busy: _busy, onTap: _smartImport),
          const SizedBox(height: 16),
          // 2) Or pick a specific type (individual icons).
          AppPanel(
            title: 'Import a specific type',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _ImportTile(
                  icon: Icons.inventory_2_rounded,
                  label: 'Stock\n& items',
                  busy: _busy,
                  onTap: () => _importUniversal(ImportKind.products),
                ),
                _ImportTile(
                  icon: Icons.people_alt_rounded,
                  label: 'Clients',
                  busy: _busy,
                  onTap: () => _importUniversal(ImportKind.customers),
                ),
                _ImportTile(
                  icon: Icons.receipt_long_rounded,
                  label: 'Sales\n(history)',
                  busy: _busy,
                  onTap: () => _importUniversal(ImportKind.sales),
                ),
                _ImportTile(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Expenses',
                  busy: _busy,
                  onTap: () => _importUniversal(ImportKind.expenses),
                ),
                _ImportTile(
                  icon: Icons.contacts_rounded,
                  label: 'Phone\ncontacts',
                  busy: _busy,
                  onTap: _importContacts,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 3) Sample templates + CSV export (round-trip).
          AppPanel(
            title: 'Templates & export',
            child: Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () =>
                            _downloadTemplate(ImportKind.products, 'products'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Products sample'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _downloadTemplate(
                          ImportKind.customers,
                          'customers',
                        ),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Customers sample'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _downloadTemplate(ImportKind.sales, 'sales'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Sales sample'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () =>
                            _downloadTemplate(ImportKind.expenses, 'expenses'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                  label: const Text('Expenses sample'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _exportCsv(ImportKind.products, 'products'),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Export products'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _exportCsv(ImportKind.customers, 'customers'),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Export customers'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _DuplicateCleanupPanel(),
          const _OpeningBalanceBackfillPanel(),
          const SizedBox(height: 16),
          AppPanel(
            title: 'Import from Zobaze',
            action: const AppTag(
              label: 'MIGRATION',
              icon: Icons.swap_horiz_rounded,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Moving from Zobaze? Export your Items and Customers as Excel '
                  '(.xlsx) from the Zobaze app, then load them here. Existing '
                  'records with the same details are updated, not duplicated.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.upload_file_rounded),
                  label: Text(
                    _busy ? 'Importing...' : 'Choose Zobaze file (.xlsx)',
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 16),
            _Banner(
              icon: Icons.error_rounded,
              color: AppPalette.error,
              title: 'Import failed',
              body: _error!,
            ),
          ],
          if (_successText != null) ...<Widget>[
            const SizedBox(height: 16),
            _Banner(
              icon: Icons.check_circle_rounded,
              color: AppPalette.success,
              title: 'Import complete',
              body: _successText!,
            ),
          ],
          if (_result != null) ...<Widget>[
            const SizedBox(height: 16),
            _Banner(
              icon: Icons.check_circle_rounded,
              color: AppPalette.success,
              title: 'Import complete',
              body:
                  '${_result!.inventory} product(s), ${_result!.customers} '
                  'customer(s), and ${_result!.sales} receipt(s) imported.'
                  '\n\n${_result!.warnings.join('\n\n')}',
            ),
          ],
        ],
      ),
    );
  }
}

/// Big primary "import any file" card that auto-detects the data type.
class _SmartImportCard extends StatelessWidget {
  const _SmartImportCard({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AppPanel(
      title: 'Smart import',
      action: const AppTag(label: 'ANY APP', icon: Icons.auto_awesome_rounded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Have an export from Zobaze, Vyapar, Khatabook, Excel — anything? '
            'Pick the file and we auto-detect whether it is products, customers '
            'or sales, match the columns, and let you confirm before importing.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: busy ? null : onTap,
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const Text('Import any file (.csv / .xlsx)'),
          ),
        ],
      ),
    );
  }
}

/// A tappable icon tile for importing one specific data type.
class _ImportTile extends StatelessWidget {
  const _ImportTile({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: 78,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.borderSoft),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, color: AppPalette.primary, size: 26),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Cleans up receipts duplicated by the old import id bug.
///
/// Hidden entirely when there is nothing to clean, so it never invites a
/// destructive action on a healthy database. Always previews before removing:
/// identical content cannot prove a double import - a shop can legitimately
/// ring up the same sale twice in a day - so the decision stays with the owner.
class _DuplicateCleanupPanel extends ConsumerStatefulWidget {
  const _DuplicateCleanupPanel();

  @override
  ConsumerState<_DuplicateCleanupPanel> createState() =>
      _DuplicateCleanupPanelState();
}

class _DuplicateCleanupPanelState
    extends ConsumerState<_DuplicateCleanupPanel> {
  List<ImportedDuplicateGroup>? _groups;
  bool _busy = false;
  String? _done;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final found = await ref
        .read(salesRepositoryProvider)
        .findImportedSaleDuplicates();
    if (!mounted) return;
    setState(() => _groups = found);
  }

  Future<void> _clean() async {
    setState(() => _busy = true);
    try {
      final removed = await ref
          .read(salesRepositoryProvider)
          .removeImportedSaleDuplicates();
      if (!mounted) return;
      setState(() {
        _done = '$removed duplicate receipt(s) removed from History.';
        _groups = const <ImportedDuplicateGroup>[];
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final groups = _groups ?? const <ImportedDuplicateGroup>[];
    final extras = groups.fold<int>(0, (sum, g) => sum + g.extras);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove duplicate receipts?'),
        content: Text(
          'This keeps one copy of each receipt and removes $extras extra '
          'row(s) from History.\n\n'
          'If your shop genuinely rang up the same sale twice on a day, that '
          'copy would be removed too. Nothing is erased permanently - the rows '
          'are retired and stock and customer balances are untouched.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Remove $extras'),
          ),
        ],
      ),
    );
    if (ok == true) await _clean();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (_done != null) {
      return AppPanel(title: 'Duplicate receipts', child: Text(_done!));
    }
    // Nothing to clean: stay out of the way rather than offering a
    // destructive button with no work to do.
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();

    final extras = groups.fold<int>(0, (sum, g) => sum + g.extras);
    return AppPanel(
      title: 'Duplicate receipts',
      action: const AppTag(
        label: 'CLEANUP',
        icon: Icons.cleaning_services_rounded,
        tone: AppTone.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '$extras imported receipt(s) look like copies of another one, '
            'across ${groups.length} sale(s). Older builds gave every import '
            'a fresh id, so re-importing a file added the sales again instead '
            'of updating them.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final g in groups.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• ${g.date} · ${formatCurrency(g.total)}'
                '${g.customerName.isEmpty ? '' : ' · ${g.customerName}'}'
                ' — ${g.copies} copies',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (groups.length > 5)
            Text(
              '…and ${groups.length - 5} more.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _confirm,
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: Text(_busy ? 'Cleaning…' : 'Review & remove duplicates'),
          ),
        ],
      ),
    );
  }
}

/// One-time repair for customers imported before opening balances were
/// recorded: their khata is empty even though they owe money.
///
/// Hidden when there is nothing to repair. Records the balance already on the
/// account rather than inventing one, and labels it "carried over" so it is
/// never mistaken for a real sale.
class _OpeningBalanceBackfillPanel extends ConsumerStatefulWidget {
  const _OpeningBalanceBackfillPanel();

  @override
  ConsumerState<_OpeningBalanceBackfillPanel> createState() =>
      _OpeningBalanceBackfillPanelState();
}

class _OpeningBalanceBackfillPanelState
    extends ConsumerState<_OpeningBalanceBackfillPanel> {
  int? _pending;
  bool _busy = false;
  String? _done;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    final count = await ref
        .read(customerRepositoryProvider)
        .countUnexplainedBalances();
    if (!mounted) return;
    setState(() => _pending = count);
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final written = await ref
          .read(customerRepositoryProvider)
          .backfillOpeningBalances();
      if (!mounted) return;
      setState(() {
        _done = '$written customer(s) now show an opening balance in Khata.';
        _pending = 0;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done != null) {
      return AppPanel(title: 'Khata opening balances', child: Text(_done!));
    }
    final pending = _pending;
    if (pending == null || pending == 0) return const SizedBox.shrink();

    return AppPanel(
      title: 'Khata opening balances',
      action: const AppTag(
        label: 'REPAIR',
        icon: Icons.build_rounded,
        tone: AppTone.info,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '$pending customer(s) owe money but have nothing in their khata to '
            'explain it, because older imports set a balance without recording '
            'where it came from. This adds one "carried over" entry each, dated '
            'to when the customer was added. Nothing is recalculated and no '
            'balance changes.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.history_edu_rounded),
            label: Text(_busy ? 'Writing…' : 'Add opening balances'),
          ),
        ],
      ),
    );
  }
}

/// Live progress dialog shown while an import pushes rows to the server.
class _ImportProgressDialog extends StatelessWidget {
  const _ImportProgressDialog({required this.total, required this.progress});

  final int total;
  final ValueNotifier<int> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: ValueListenableBuilder<int>(
        valueListenable: progress,
        builder: (context, done, _) {
          final frac = total == 0 ? 0.0 : done / total;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Importing & syncing…',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              const Text(
                'Saving each row to your cloud so it never disappears.',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: frac, minHeight: 8),
              ),
              const SizedBox(height: 10),
              Text(
                '$done of $total',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Top-level entry for compute(): maps rows off the UI thread. Must be a
/// top-level function (no captured widget state) so it's sendable to an isolate.
MappedImport _mapRowsIsolate((ParsedTable, ImportKind, ColumnMapping?) args) =>
    mapRows(args.$1, args.$2, mapping: args.$3);
