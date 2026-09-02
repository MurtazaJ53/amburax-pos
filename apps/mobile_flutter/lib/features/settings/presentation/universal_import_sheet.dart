import 'package:flutter/material.dart';

import '../../../core/import/universal_import.dart';
import '../../../core/theme/app_colors.dart';

/// Column-mapping preview for a picked file. Shows the auto-detected mapping and
/// lets the user reassign any field to a different column (so *any* layout can
/// be imported), then returns the confirmed [ColumnMapping] — or null on cancel.
Future<ColumnMapping?> showMappingSheet(
  BuildContext context, {
  required ParsedTable table,
  required ImportKind kind,
  required String title,
}) {
  return showModalBottomSheet<ColumnMapping>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MappingSheet(table: table, kind: kind, title: title),
  );
}

class _MappingSheet extends StatefulWidget {
  const _MappingSheet({
    required this.table,
    required this.kind,
    required this.title,
  });

  final ParsedTable table;
  final ImportKind kind;
  final String title;

  @override
  State<_MappingSheet> createState() => _MappingSheetState();
}

class _MappingSheetState extends State<_MappingSheet> {
  late Map<String, int?> _selection;

  @override
  void initState() {
    super.initState();
    final auto = autoMap(widget.table.headers, widget.kind);
    _selection = <String, int?>{
      for (final f in importSchemas[widget.kind]!) f.key: auto.columnFor(f.key),
    };
  }

  List<ImportField> get _fields => importSchemas[widget.kind]!;

  bool get _requiredSatisfied =>
      _fields.where((f) => f.required).every((f) => _selection[f.key] != null);

  int get _rowsIn => widget.table.rows.length;

  ColumnMapping _currentMapping() {
    final map = <String, int>{};
    _selection.forEach((k, v) {
      if (v != null) map[k] = v;
    });
    return ColumnMapping(widget.table.headers, map);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final preview = mapRows(
      widget.table,
      widget.kind,
      mapping: _currentMapping(),
    );
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colors.borderSoft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'We matched your columns automatically. Adjust any that are wrong, '
                'then import. ${preview.rows.length} of $_rowsIn row(s) look valid.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: <Widget>[
                    ..._fields.map(_fieldRow),
                    const SizedBox(height: 16),
                    _previewTable(preview),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_requiredSatisfied && preview.rows.isNotEmpty)
                          ? () => Navigator.pop(context, _currentMapping())
                          : null,
                      child: Text('Import ${preview.rows.length}'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _fieldRow(ImportField f) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    f.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (f.required)
                  Text(' *', style: TextStyle(color: colors.textSecondary)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 16),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<int?>(
              initialValue: _selection[f.key],
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<int?>>[
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('— skip —'),
                ),
                ...List<DropdownMenuItem<int?>>.generate(
                  widget.table.headers.length,
                  (i) => DropdownMenuItem<int?>(
                    value: i,
                    child: Text(
                      widget.table.headers[i].isEmpty
                          ? 'Column ${i + 1}'
                          : widget.table.headers[i],
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _selection[f.key] = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewTable(MappedImport preview) {
    final colors = AppColors.of(context);
    final fields = _fields.where((f) => _selection[f.key] != null).toList();
    final sample = preview.rows.take(3).toList();
    if (sample.isEmpty) {
      return Text(
        'No valid rows with the current mapping.',
        style: TextStyle(color: colors.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Preview',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            headingRowHeight: 34,
            dataRowMinHeight: 30,
            dataRowMaxHeight: 40,
            columns: fields
                .map((f) => DataColumn(label: Text(f.label)))
                .toList(),
            rows: sample
                .map(
                  (row) => DataRow(
                    cells: fields
                        .map((f) => DataCell(Text(row[f.key] ?? '')))
                        .toList(),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
