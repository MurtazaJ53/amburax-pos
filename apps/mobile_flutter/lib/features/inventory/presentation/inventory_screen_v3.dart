import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/database/mobile_repository.dart';
import '../../../core/images/product_image_store.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/session/mobile_session_controller.dart';
import '../../../core/sync/mobile_sync_coordinator.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/premium_components.dart';
import '../../pos/presentation/pos_scanner_sheet.dart';
import '../../../core/receipt/barcode_labels_pdf.dart';
import 'reorder_list_screen.dart';
import 'variant_product_sheet.dart';
import '../../../ui/ui.dart';
import '../../../core/inventory/stock_line.dart';

/// Redesigned Inventory Screen v3.0
/// Simple, Clean, Premium, Professional
class InventoryScreenV3 extends ConsumerStatefulWidget {
  const InventoryScreenV3({super.key});

  @override
  ConsumerState<InventoryScreenV3> createState() => _InventoryScreenV3State();
}

/// Pull the first frame that belongs to this app out of a stack trace, so an
/// error shown to the user points at a real file and line instead of being an
/// untraceable one-liner.
String _firstAppFrame(StackTrace stackTrace) {
  // Show the frame that actually threw (#0) AND the first frame in our own
  // code. Only reporting our frame hid the real cause inside a package, which
  // is why this crash survived several attempts to pin it down.
  final lines = stackTrace
      .toString()
      .split("\n")
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return '';
  final top = lines.first;
  final app = lines.firstWhere(
    (l) => l.contains('package:business_hub_mobile/'),
    orElse: () => '',
  );
  if (app.isEmpty || app == top) return top;
  return '$top\n$app';
}

class _InventoryScreenV3State extends ConsumerState<InventoryScreenV3> {
  /// Units of measurement offered in the item form.
  static const List<String> _unitOptions = <String>[
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

  final TextEditingController _searchController = TextEditingController();

  String _search = '';
  String? _selectedCategory;
  bool _showLowStockOnly = false;
  Timer? _searchDebounce;

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _search = value);
      // Also pull matching items from the server (in case they're outside the
      // locally-cached window) and merge them in; the catalog stream updates.
      ref.read(mobileSyncCoordinatorProvider).searchInventoryFromServer(value);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(inventoryCategoriesProvider).asData?.value ??
        const <InventoryCategorySummary>[];
    final catalogFilter = InventoryCatalogFilter(
      search: _search,
      category: _selectedCategory,
      pageSize: 250,
      lowStockOnly: _showLowStockOnly,
    );
    final items =
        ref.watch(inventoryCatalogPageProvider(catalogFilter)).asData?.value ??
        const <InventoryCatalogItem>[];

    final filteredItems = items.where((item) {
      if (_search.isNotEmpty &&
          !item.name.toLowerCase().contains(_search.toLowerCase())) {
        return false;
      }
      if (_selectedCategory != null && item.category != _selectedCategory) {
        return false;
      }
      if (_showLowStockOnly && item.stock > 5) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.of(context).background,
      body: _buildCatalog(
        context,
        categories,
        filteredItems,
        catalogueScopeNotice(
          shown: filteredItems.length,
          total:
              ref
                  .watch(inventoryCatalogCountProvider(catalogFilter))
                  .asData
                  ?.value ??
              filteredItems.length,
          searching: _search.trim().isNotEmpty,
        ),
      ),
      // Add item FAB
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddChooser(context),
        backgroundColor: AppPalette.primary,
        icon: const Icon(Icons.add_rounded, size: 24),
        label: Text(
          'Add Item',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// Per-item audit trail: how stock changed and why.
  void _showStockHistory(BuildContext context, InventoryCatalogItem item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.of(context).background,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Stock history · ${item.name}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 360,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final moves =
                          ref
                              .watch(stockMovementsProvider(item.id))
                              .asData
                              ?.value ??
                          const <StockMovement>[];
                      if (moves.isEmpty) {
                        return const Center(
                          child: Text('No stock movements recorded yet.'),
                        );
                      }
                      return ListView.separated(
                        itemCount: moves.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final m = moves[index];
                          final sign = m.isIn ? '+' : '';
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              m.isIn
                                  ? Icons.south_west_rounded
                                  : Icons.north_east_rounded,
                              color: m.isIn
                                  ? AppPalette.success
                                  : AppPalette.error,
                            ),
                            title: Text(
                              '${m.reason} · $sign${formatQty(m.delta)}'
                              '${m.balanceAfter != null ? ' → ${formatQty(m.balanceAfter!)}' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${m.createdAt.toIso8601String().split('T').first}'
                              '${m.note.isNotEmpty ? ' · ${m.note}' : ''}'
                              '${m.actorName != null ? ' · ${m.actorName}' : ''}',
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Let the user pick a simple single item or a multi-variant product.
  void _showAddChooser(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.add_box_rounded),
              title: const Text('Single item'),
              subtitle: const Text('One product, one price and stock'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showAddItemSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.category_rounded),
              title: const Text('Product with variants'),
              subtitle: const Text(
                'Sizes/colours, each with own price & stock',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: AppColors.of(context).background,
                  builder: (_) => const VariantProductSheet(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Scrollable catalog: a floating toolbar (search + actions + filter chips)
  /// that slides away as you scroll down so the product list fills the screen,
  /// and snaps back the moment you scroll up. The screen title / back / sync
  /// already live in the app shell header, so we don't repeat them here.
  Widget _buildCatalog(
    BuildContext context,
    List<InventoryCategorySummary> categories,
    List<InventoryCatalogItem> items,
    String? scopeNotice,
  ) {
    final colors = AppColors.of(context);
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          floating: true,
          snap: true,
          primary: false,
          automaticallyImplyLeading: false,
          backgroundColor: colors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 74,
          titleSpacing: 16,
          title: Padding(
            padding: const EdgeInsets.only(right: 4, top: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: PremiumSearchBar(
                    controller: _searchController,
                    hintText: L.of(context).invSearchHint,
                    onChanged: _onSearchChanged,
                    onClear: () {
                      _searchDebounce?.cancel();
                      setState(() => _search = '');
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _ToolbarIconButton(
                  icon: Icons.category_rounded,
                  tooltip: 'Categories',
                  onTap: () => context.push('/categories'),
                ),
                const SizedBox(width: 6),
                _ToolbarIconButton(
                  icon: Icons.playlist_add_rounded,
                  tooltip: 'Bulk add',
                  onTap: () => _showBulkAddSheet(context),
                ),
              ],
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: _buildChipsBar(categories),
          ),
        ),
        // Buying decisions are a daily job, so surface the reorder list here
        // rather than leaving reorder_level as data nobody acts on.
        SliverToBoxAdapter(child: _buildReorderBanner(context)),
        if (scopeNotice != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverToBoxAdapter(
              child: AppNotice(
                message: scopeNotice,
                tone: AppTone.warning,
                icon: Icons.filter_list_rounded,
              ),
            ),
          ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyStateWidget(
              icon: Icons.inventory_2_rounded,
              title: 'No items found',
              message: _search.isEmpty
                  ? 'Start adding products to your inventory'
                  : 'Try a different search term or filter',
            ),
          )
        else
          SliverList.builder(
            itemCount: items.length,
            itemBuilder: (context, index) => _buildItemRow(items[index]),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ],
    );
  }

  /// Horizontal filter rail: All · Low stock toggle · one chip per category.
  Widget _buildChipsBar(List<InventoryCategorySummary> categories) {
    final colors = AppColors.of(context);
    return Container(
      height: 50,
      color: colors.surface,
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        children: <Widget>[
          _buildCategoryChip(
            label: 'All',
            isSelected: _selectedCategory == null && !_showLowStockOnly,
            onTap: () => setState(() {
              _selectedCategory = null;
              _showLowStockOnly = false;
            }),
          ),
          const SizedBox(width: 8),
          _buildLowStockChip(),
          for (final category in categories) ...<Widget>[
            const SizedBox(width: 8),
            _buildCategoryChip(
              label: category.category,
              isSelected: _selectedCategory == category.category,
              onTap: () =>
                  setState(() => _selectedCategory = category.category),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLowStockChip() {
    final colors = AppColors.of(context);
    final selected = _showLowStockOnly;
    return Material(
      color: selected
          ? AppPalette.error.withValues(alpha: 0.12)
          : colors.surfaceStrong,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _showLowStockOnly = !_showLowStockOnly),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                size: 15,
                color: AppPalette.error,
              ),
              const SizedBox(width: 6),
              Text(
                'Low stock',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppPalette.error : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReorderBanner(BuildContext context) {
    final due =
        ref.watch(reorderListProvider).asData?.value ?? const <ReorderItem>[];
    if (due.isEmpty) return const SizedBox.shrink();
    final out = due.where((i) => i.isOutOfStock).length;
    final accent = out > 0 ? AppPalette.error : AppPalette.warning;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/settings/reorder'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.shopping_cart_checkout_rounded, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    out > 0
                        ? '${due.length} to reorder - $out already out of stock'
                        : '${due.length} item(s) running low - tap to order',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected
          ? toneColorsOf(context, AppTone.primary).background
          : AppColors.of(context).surfaceStrong,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? toneColorsOf(context, AppTone.primary).foreground
                  : AppColors.of(context).textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// A 56x56 product photo for list rows, or null so [EnhancedListItem] falls
  /// back to its coloured icon tile when the item has no image.
  Widget? _productThumb(InventoryCatalogItem item) {
    final path = item.imagePath;
    if (path == null || path.isEmpty || !File(path).existsSync()) return null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.file(
        File(path),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const SizedBox(width: 56, height: 56),
      ),
    );
  }

  Widget _buildItemRow(InventoryCatalogItem item) {
    return EnhancedListItem(
      title: item.name,
      subtitle:
          '${item.category} • Stock: ${formatQty(item.stock)}'
          '${item.unit != null && item.unit!.isNotEmpty ? ' ${item.unit}' : ''}'
          ' • ${formatCurrency(item.price)}',
      leading: _productThumb(item),
      leadingIcon: Icons.inventory_2_rounded,
      leadingColor: item.isLowStock ? AppPalette.error : AppPalette.inventory,
      trailing: StatusBadge(
        label: item.isLowStock ? 'Low' : 'OK',
        color: item.isLowStock ? AppPalette.error : AppPalette.success,
      ),
      onTap: () => _showItemDetails(context, item),
    );
  }

  void _showItemDetails(BuildContext context, InventoryCatalogItem item) {
    final session = ref.read(mobileSessionProvider).asData?.value;
    final canManage =
        session != null && (session.isOwnerLike || session.isManager);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.of(context).background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.of(context).border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Item details
            Text(
              item.name,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.of(context).textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.category,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: 24),

            // Metrics
            Row(
              children: [
                Expanded(
                  child: _buildMetricBox(
                    label: 'Price',
                    value: formatCurrency(item.price),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricBox(
                    label: 'Stock',
                    value: formatQty(item.stock),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showRestockSheet(context, item);
                    },
                    icon: const Icon(Icons.add_box_rounded),
                    label: Text(L.of(context).invRestock),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddItemSheet(context, existing: item);
                    },
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('Edit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddItemSheet(context, duplicateOf: item);
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Duplicate'),
                  ),
                ),
                if (canManage)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _confirmDeleteItem(item);
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppPalette.error,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _printLabels(item);
              },
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Print price labels'),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showStockHistory(context, item);
              },
              icon: const Icon(Icons.history_rounded),
              label: const Text('Stock movement history'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBox({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.of(context).borderSoft, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.of(context).textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.of(context).textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddItemSheet(
    BuildContext context, {
    InventoryCatalogItem? existing,
    InventoryCatalogItem? duplicateOf,
  }) {
    final isEdit = existing != null;
    final source = existing ?? duplicateOf;
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(
      text: source == null
          ? ''
          : (duplicateOf != null ? '${source.name} (copy)' : source.name),
    );
    final priceController = TextEditingController(
      text: source != null ? source.price.toStringAsFixed(2) : '',
    );
    final stockController = TextEditingController(
      text: '${duplicateOf != null ? 0 : (source?.stock ?? 0)}',
    );
    final categoryController = TextEditingController(
      text: source?.category ?? 'General',
    );
    final skuController = TextEditingController(
      text: duplicateOf != null ? '' : (source?.sku ?? ''),
    );
    final hsnController = TextEditingController(text: source?.hsnCode ?? '');
    final gstController = TextEditingController(
      text: source != null ? source.gstRate.toString() : '0',
    );
    final costController = TextEditingController(
      text: (source?.costPrice ?? 0) > 0
          ? source!.costPrice!.toStringAsFixed(2)
          : '',
    );
    final descriptionController = TextEditingController(
      text: source?.description ?? '',
    );
    final reorderController = TextEditingController(
      text: source?.reorderLevel != null ? '${source!.reorderLevel}' : '',
    );
    var selectedUnit = source?.unit ?? _unitOptions.first;
    if (!_unitOptions.contains(selectedUnit)) {
      selectedUnit = _unitOptions.first;
    }
    var priceIncludesTax = source?.priceIncludesTax ?? true;
    // A duplicate starts without a photo so it never shares (and later orphans)
    // the original's image file.
    String? imagePath = duplicateOf != null ? null : source?.imagePath;
    var isSaving = false;
    final imageStore = ProductImageStore();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> pickImage(ImageSource src) async {
              try {
                final stored = await imageStore.pickAndStore(source: src);
                if (stored == null) return;
                setSheetState(() => imagePath = stored);
              } catch (error) {
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text('Could not add photo: $error')),
                );
              }
            }

            void openPhotoOptions() {
              showModalBottomSheet<void>(
                context: sheetContext,
                builder: (optionsContext) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.photo_camera_rounded),
                        title: Text(L.of(context).invTakePhoto),
                        onTap: () {
                          Navigator.pop(optionsContext);
                          pickImage(ImageSource.camera);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library_rounded),
                        title: Text(L.of(context).invChooseGallery),
                        onTap: () {
                          Navigator.pop(optionsContext);
                          pickImage(ImageSource.gallery);
                        },
                      ),
                      if (imagePath != null)
                        ListTile(
                          leading: const Icon(Icons.delete_outline_rounded),
                          title: Text(L.of(context).invRemovePhoto),
                          onTap: () {
                            Navigator.pop(optionsContext);
                            setSheetState(() => imagePath = null);
                          },
                        ),
                    ],
                  ),
                ),
              );
            }

            Future<void> saveItem() async {
              if (formKey.currentState?.validate() != true || isSaving) {
                return;
              }

              setSheetState(() => isSaving = true);
              try {
                final price = double.tryParse(priceController.text.trim()) ?? 0;
                final openingStock =
                    double.tryParse(stockController.text.trim()) ?? 0;
                final gstRate = double.tryParse(gstController.text.trim()) ?? 0;
                final costText = costController.text.trim();
                final costPrice = costText.isEmpty
                    ? null
                    : double.tryParse(costText);
                final reorderText = reorderController.text.trim();
                final reorderLevel = reorderText.isEmpty
                    ? null
                    : int.tryParse(reorderText);
                final description = descriptionController.text.trim();

                final coordinator = ref.read(mobileSyncCoordinatorProvider);
                if (isEdit) {
                  await coordinator.updateInventoryItem(
                    itemId: existing.id,
                    name: nameController.text.trim(),
                    sellPrice: price,
                    stock: openingStock,
                    category: categoryController.text.trim(),
                    sku: skuController.text.trim(),
                    hsnCode: hsnController.text.trim(),
                    gstRate: gstRate,
                    priceIncludesTax: priceIncludesTax,
                    costPrice: costPrice ?? existing.costPrice,
                    size: existing.size ?? '',
                    subcategory: existing.subcategory ?? '',
                    description: description,
                    createdAt: existing.createdAt,
                    imagePath: imagePath,
                    unit: selectedUnit,
                    reorderLevel: reorderLevel,
                  );
                } else {
                  await coordinator.createInventoryItem(
                    name: nameController.text.trim(),
                    sellPrice: price,
                    openingStock: openingStock,
                    category: categoryController.text.trim(),
                    sku: skuController.text.trim(),
                    hsnCode: hsnController.text.trim(),
                    gstRate: gstRate,
                    priceIncludesTax: priceIncludesTax,
                    costPrice: costPrice,
                    description: description,
                    imagePath: imagePath,
                    unit: selectedUnit,
                    reorderLevel: reorderLevel,
                  );
                }

                if (!sheetContext.mounted) {
                  return;
                }
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${nameController.text.trim()} ${isEdit ? 'updated' : 'added'}.',
                    ),
                  ),
                );
              } catch (error, stackTrace) {
                // Surface where it actually broke. A bare message ("Null check
                // operator used on a null value") is untraceable in the field,
                // so include the first app frame and log the full trace.
                debugPrint('Inventory save failed: $error\n$stackTrace');
                if (!sheetContext.mounted) {
                  return;
                }
                setSheetState(() => isSaving = false);
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Save failed: $error\n${_firstAppFrame(stackTrace)}',
                    ),
                    duration: const Duration(seconds: 12),
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.of(sheetContext).background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.of(sheetContext).border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            isEdit ? 'Edit Item' : 'Add New Item',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: AppColors.of(sheetContext).textPrimary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: GestureDetector(
                              onTap: openPhotoOptions,
                              child: Container(
                                width: 104,
                                height: 104,
                                decoration: BoxDecoration(
                                  color: AppColors.of(sheetContext).surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppColors.of(sheetContext).border,
                                  ),
                                  image: imagePath != null
                                      ? DecorationImage(
                                          image: FileImage(File(imagePath!)),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: imagePath != null
                                    ? null
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_a_photo_rounded,
                                            color: AppColors.of(
                                              sheetContext,
                                            ).textSecondary,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Add photo',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: AppColors.of(
                                                sheetContext,
                                              ).textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            textCapitalization: TextCapitalization.sentences,
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Item name',
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Item name is required'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: priceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Selling price',
                            ),
                            validator: (value) {
                              final parsed = double.tryParse(
                                value?.trim() ?? '',
                              );
                              if (parsed == null || parsed <= 0) {
                                return 'Enter a valid selling price';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: costController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Cost / purchase price (optional)',
                              helperText: 'Drives profit margin & valuation',
                            ),
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) return null;
                              final parsed = double.tryParse(text);
                              if (parsed == null || parsed < 0) {
                                return 'Enter a valid cost price';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: stockController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Opening stock',
                            ),
                            validator: (value) {
                              final parsed = double.tryParse(
                                value?.trim() ?? '',
                              );
                              if (parsed == null || parsed < 0) {
                                return 'Enter stock as 0 or more';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedUnit,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Unit',
                                  ),
                                  items: <DropdownMenuItem<String>>[
                                    for (final u in _unitOptions)
                                      DropdownMenuItem<String>(
                                        value: u,
                                        child: Text(u),
                                      ),
                                  ],
                                  onChanged: (value) => setSheetState(
                                    () => selectedUnit =
                                        value ?? _unitOptions.first,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: reorderController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Reorder level',
                                    helperText: 'Low-stock alert',
                                  ),
                                  validator: (value) {
                                    final text = value?.trim() ?? '';
                                    if (text.isEmpty) return null;
                                    final parsed = int.tryParse(text);
                                    if (parsed == null || parsed < 0) {
                                      return 'Enter 0 or more';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            textCapitalization: TextCapitalization.sentences,
                            controller: categoryController,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            textCapitalization: TextCapitalization.sentences,
                            controller: skuController,
                            decoration: InputDecoration(
                              labelText: 'SKU / barcode (optional)',
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                                tooltip: 'Scan barcode',
                                onPressed: () async {
                                  final code =
                                      await showModalBottomSheet<String>(
                                        context: sheetContext,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (_) => const PosScannerSheet(),
                                      );
                                  if (code != null && code.trim().isNotEmpty) {
                                    skuController.text = code.trim();
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: descriptionController,
                            maxLines: 2,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Description / notes (optional)',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            textCapitalization: TextCapitalization.sentences,
                            controller: hsnController,
                            decoration: const InputDecoration(
                              labelText: 'HSN/SAC optional',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: gstController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'GST rate %',
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: priceIncludesTax,
                            activeThumbColor: AppPalette.primary,
                            title: const Text('Price includes GST'),
                            onChanged: (value) {
                              setSheetState(() => priceIncludesTax = value);
                            },
                          ),
                          const SizedBox(height: 20),
                          PrimaryActionButton(
                            label: isSaving
                                ? 'Saving...'
                                : (isEdit ? 'Save Changes' : 'Create Item'),
                            icon: isEdit
                                ? Icons.check_rounded
                                : Icons.add_rounded,
                            onPressed: isSaving ? null : saveItem,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      nameController.dispose();
      priceController.dispose();
      stockController.dispose();
      categoryController.dispose();
      skuController.dispose();
      hsnController.dispose();
      gstController.dispose();
      costController.dispose();
      descriptionController.dispose();
      reorderController.dispose();
    });
  }

  /// Print price/barcode stickers for an item. Asks how many, because a shop
  /// labelling new stock wants a run of them, not one.
  Future<void> _printLabels(InventoryCatalogItem item) async {
    final controller = TextEditingController(text: '12');
    final copies = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Labels for ${item.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              (item.sku ?? '').trim().isEmpty
                  ? 'This item has no SKU, so the label will print name and '
                        'price without a barcode.'
                  : 'Barcode: ${item.sku}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'How many labels?',
                helperText: '24 fit on one A4 sticker sheet',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.trim()) ?? 0,
            ),
            child: const Text('Print'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (copies == null || copies < 1 || !mounted) return;

    final shop = ref.read(shopInfoProvider).asData?.value;
    final bytes = await buildBarcodeLabelsPdf(
      shopName: shop?.name ?? '',
      labels: <LabelRequest>[
        LabelRequest(
          name: item.name,
          price: item.price,
          code: item.sku ?? '',
          size: item.size,
          copies: copies,
        ),
      ],
    );
    await Printing.layoutPdf(onLayout: (_) => bytes);
  }

  void _showRestockSheet(BuildContext context, InventoryCatalogItem item) {
    final qtyController = TextEditingController();
    final priceController = TextEditingController(
      text: item.price.toStringAsFixed(2),
    );
    var isSaving = false;
    var setExact = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> save() async {
              final entered = double.tryParse(qtyController.text.trim()) ?? 0;
              // "Set exact" repairs a wrong count (e.g. stock that went
              // negative after duplicate imports); "Add" is the normal restock.
              final addQty = setExact ? entered - item.stock : entered;
              if (isSaving) return;
              if (!setExact && entered <= 0) return;
              if (setExact && entered < 0) return;
              if (addQty == 0) {
                Navigator.pop(sheetContext);
                return;
              }
              setSheetState(() => isSaving = true);
              try {
                final newPrice =
                    double.tryParse(priceController.text.trim()) ?? item.price;
                await ref
                    .read(mobileSyncCoordinatorProvider)
                    .updateInventoryItem(
                      itemId: item.id,
                      name: item.name,
                      sellPrice: newPrice,
                      stock: item.stock + addQty,
                      category: item.category,
                      sku: item.sku ?? '',
                      hsnCode: item.hsnCode ?? '',
                      gstRate: item.gstRate,
                      priceIncludesTax: item.priceIncludesTax,
                      costPrice: item.costPrice,
                      size: item.size ?? '',
                      subcategory: item.subcategory ?? '',
                      description: item.description ?? '',
                      createdAt: item.createdAt,
                      // Preserve local-only fields — updateInventoryItem clears
                      // any it isn't given.
                      imagePath: item.imagePath,
                      unit: item.unit,
                      reorderLevel: item.reorderLevel,
                    );
                await ref
                    .read(inventoryRepositoryProvider)
                    .logStockAdjustment(
                      itemId: item.id,
                      itemName: item.name,
                      oldStock: item.stock,
                      newStock: item.stock + addQty,
                      actorName: ref
                          .read(mobileSessionProvider)
                          .asData
                          ?.value
                          ?.user
                          .displayName,
                      note: setExact
                          ? 'Stock corrected to $entered'
                          : 'Restocked +$addQty',
                    );
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${item.name}: +${formatQty(addQty)} (now ${formatQty(item.stock + addQty)}).',
                    ),
                  ),
                );
              } catch (error, stackTrace) {
                debugPrint('Restock failed: $error\n$stackTrace');
                if (!sheetContext.mounted) return;
                setSheetState(() => isSaving = false);
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Restock failed: $error\n${_firstAppFrame(stackTrace)}',
                    ),
                    duration: const Duration(seconds: 12),
                  ),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.of(sheetContext).background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.of(sheetContext).border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Restock',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.of(sheetContext).textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.name} · current stock ${formatQty(item.stock)}',
                        style: TextStyle(
                          color: AppColors.of(sheetContext).textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // A count can be wrong (duplicate imports left some items
                      // negative), so allow correcting it outright instead of
                      // only ever adding to a number that was never right.
                      SegmentedButton<bool>(
                        segments: <ButtonSegment<bool>>[
                          ButtonSegment<bool>(
                            value: false,
                            label: Text(L.of(context).invAddStock),
                            icon: Icon(Icons.add_rounded, size: 18),
                          ),
                          ButtonSegment<bool>(
                            value: true,
                            label: Text('Set exact'),
                            icon: Icon(Icons.tune_rounded, size: 18),
                          ),
                        ],
                        selected: <bool>{setExact},
                        onSelectionChanged: (selection) =>
                            setSheetState(() => setExact = selection.first),
                      ),
                      if (item.stock < 0) ...<Widget>[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppPalette.error.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'This item shows ${formatQty(item.stock)} in stock, '
                            'which cannot be right. Use "Set exact" to enter '
                            'the real count from the shelf.',
                            style: Theme.of(sheetContext).textTheme.bodySmall,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: setExact
                              ? 'Actual stock on the shelf'
                              : 'Add quantity',
                          helperText: setExact
                              ? 'Replaces the current count'
                              : 'Added to the current count',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Selling price',
                        ),
                      ),
                      const SizedBox(height: 20),
                      PrimaryActionButton(
                        label: isSaving ? 'Saving...' : 'Add stock',
                        icon: Icons.add_box_rounded,
                        onPressed: isSaving ? null : save,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      qtyController.dispose();
      priceController.dispose();
    });
  }

  Future<void> _confirmDeleteItem(InventoryCatalogItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('${item.name} will be removed from your inventory.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(mobileSyncCoordinatorProvider)
          .deleteInventoryItem(itemId: item.id, name: item.name);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${item.name} deleted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: $error')));
    }
  }

  void _showBulkAddSheet(BuildContext context) {
    final rows = <_BulkRow>[_BulkRow(), _BulkRow(), _BulkRow()];
    var isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> save() async {
              final valid = rows
                  .where(
                    (r) =>
                        r.name.text.trim().isNotEmpty &&
                        (double.tryParse(r.price.text.trim()) ?? 0) > 0,
                  )
                  .toList();
              if (valid.isEmpty || isSaving) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('Enter at least one item name and price.'),
                  ),
                );
                return;
              }
              setSheetState(() => isSaving = true);
              try {
                final coordinator = ref.read(mobileSyncCoordinatorProvider);
                for (final r in valid) {
                  await coordinator.createInventoryItem(
                    name: r.name.text.trim(),
                    sellPrice: double.parse(r.price.text.trim()),
                    openingStock: double.tryParse(r.qty.text.trim()) ?? 0,
                  );
                }
                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${valid.length} item${valid.length == 1 ? '' : 's'} added.',
                    ),
                  ),
                );
              } catch (error) {
                if (!sheetContext.mounted) return;
                setSheetState(() => isSaving = false);
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text('Bulk add failed: $error')),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.of(sheetContext).background,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.all(20),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.of(sheetContext).border,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Bulk add items',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Name and price required. Quantity optional.',
                        style: TextStyle(
                          color: AppColors.of(sheetContext).textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: rows.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final r = rows[index];
                            return Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: TextField(
                                    textCapitalization:
                                        TextCapitalization.sentences,
                                    controller: r.name,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: 'Item name',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: r.price,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: 'Price',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: r.qty,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      hintText: 'Qty',
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: rows.length <= 1
                                      ? null
                                      : () => setSheetState(
                                          () => rows.removeAt(index).dispose(),
                                        ),
                                  icon: const Icon(
                                    Icons.remove_circle_outline_rounded,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              setSheetState(() => rows.add(_BulkRow())),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add row'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      PrimaryActionButton(
                        label: isSaving ? 'Importing...' : 'Import items',
                        icon: Icons.playlist_add_check_rounded,
                        onPressed: isSaving ? null : save,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      for (final r in rows) {
        r.dispose();
      }
    });
  }
}

class _BulkRow {
  final TextEditingController name = TextEditingController();
  final TextEditingController price = TextEditingController();
  final TextEditingController qty = TextEditingController();

  void dispose() {
    name.dispose();
    price.dispose();
    qty.dispose();
  }
}

/// Square icon button used in the inventory toolbar, sized to line up with the
/// 60px search bar beside it.
class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.borderSoft),
            ),
            child: Icon(icon, size: 22, color: AppPalette.primary),
          ),
        ),
      ),
    );
  }
}
