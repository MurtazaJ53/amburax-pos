import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/mobile_models.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../ui/ui.dart';

/// Create one product that has several size/colour variants. Each variant is
/// saved as its own inventory row (own price / stock / SKU) sharing a variant
/// group, so the POS can show a single tile with a variant picker.
class VariantProductSheet extends ConsumerStatefulWidget {
  const VariantProductSheet({super.key});

  static const List<String> unitOptions = <String>[
    'pcs',
    'kg',
    'g',
    'litre',
    'ml',
    'box',
    'pack',
    'dozen',
    'metre',
    'feet',
  ];

  @override
  ConsumerState<VariantProductSheet> createState() =>
      _VariantProductSheetState();
}

class _VariantRow {
  _VariantRow();
  final TextEditingController label = TextEditingController();
  final TextEditingController price = TextEditingController();
  final TextEditingController stock = TextEditingController(text: '0');
  final TextEditingController sku = TextEditingController();
  final TextEditingController cost = TextEditingController();

  void dispose() {
    label.dispose();
    price.dispose();
    stock.dispose();
    sku.dispose();
    cost.dispose();
  }
}

class _VariantProductSheetState extends ConsumerState<VariantProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController(text: 'General');
  final _gstController = TextEditingController(text: '0');
  final List<_VariantRow> _rows = <_VariantRow>[_VariantRow(), _VariantRow()];
  String _unit = VariantProductSheet.unitOptions.first;
  bool _priceIncludesTax = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _gstController.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true || _saving) return;
    final drafts = <VariantDraft>[];
    for (final r in _rows) {
      final label = r.label.text.trim();
      if (label.isEmpty) continue;
      final price = double.tryParse(r.price.text.trim());
      if (price == null || price <= 0) continue;
      final costText = r.cost.text.trim();
      drafts.add(
        VariantDraft(
          label: label,
          sellPrice: price,
          openingStock: double.tryParse(r.stock.text.trim()) ?? 0,
          sku: r.sku.text.trim(),
          costPrice: costText.isEmpty ? null : double.tryParse(costText),
        ),
      );
    }
    if (drafts.isEmpty) {
      setState(() => _error = 'Add at least one variant with a label & price.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(mobileSyncCoordinatorProvider)
          .createVariantGroup(
            baseName: _nameController.text.trim(),
            variants: drafts,
            category: _categoryController.text.trim(),
            gstRate: double.tryParse(_gstController.text.trim()) ?? 0,
            priceIncludesTax: _priceIncludesTax,
            unit: _unit,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_nameController.text.trim()} added with ${drafts.length} '
            'variant(s).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              const AppSheetHeader(
                eyebrow: 'Inventory',
                title: 'Product with variants',
                subtitle:
                    'One product, many sizes/colours. Each variant tracks its '
                    'own price and stock.',
                icon: Icons.category_rounded,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Product name (e.g. T-Shirt)',
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Product name is required'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      textCapitalization: TextCapitalization.sentences,
                      controller: _categoryController,
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _unit,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: <DropdownMenuItem<String>>[
                        for (final u in VariantProductSheet.unitOptions)
                          DropdownMenuItem<String>(value: u, child: Text(u)),
                      ],
                      onChanged: (v) => setState(
                        () =>
                            _unit = v ?? VariantProductSheet.unitOptions.first,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _gstController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'GST rate %',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: <Widget>[
                        Switch.adaptive(
                          value: _priceIncludesTax,
                          activeThumbColor: AppPalette.primary,
                          onChanged: (v) =>
                              setState(() => _priceIncludesTax = v),
                        ),
                        const Flexible(child: Text('Incl. GST')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Variants',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _rows.length; i++) _buildVariantCard(i),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() => _rows.add(_VariantRow())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add another variant'),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppPalette.error)),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppPalette.primaryDark,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_saving ? 'Saving...' : 'Save product'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVariantCard(int index) {
    final row = _rows[index];
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSoft),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: row.label,
                  decoration: const InputDecoration(
                    labelText: 'Variant (e.g. S / Red)',
                    isDense: true,
                  ),
                ),
              ),
              if (_rows.length > 1)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Remove variant',
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _rows.removeAt(index).dispose();
                        }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  controller: row.price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: row.stock,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Stock',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  textCapitalization: TextCapitalization.sentences,
                  controller: row.sku,
                  decoration: const InputDecoration(
                    labelText: 'SKU / barcode',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: row.cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Cost (opt)',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
