import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/mobile_repository.dart';
import '../../../core/models/mobile_models.dart';
import '../../../core/providers/mobile_data_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

/// Manage product categories — rename a category across every item.
class CategoryManagementScreen extends ConsumerWidget {
  const CategoryManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories =
        ref.watch(inventoryCategoriesProvider).asData?.value ??
        const <InventoryCategorySummary>[];

    return MobileStandaloneScaffold(
      title: 'Categories',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
        children: <Widget>[
          AppPanel(
            title: 'Product categories',
            action: MobileTag(
              label: '${categories.length}',
              icon: Icons.category_rounded,
              accent: AppPalette.primary,
            ),
            child: categories.isEmpty
                ? const AppEmptyState(
                    icon: Icons.category_outlined,
                    title: 'No categories yet',
                    body: 'Categories appear here as you add products.',
                  )
                : Column(
                    children: categories
                        .map(
                          (c) => _CategoryRow(
                            summary: c,
                            onRename: () => _rename(context, ref, c),
                          ),
                        )
                        .toList(growable: false),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    InventoryCategorySummary summary,
  ) async {
    final controller = TextEditingController(text: summary.category);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || newName == summary.category) {
      return;
    }
    try {
      final count = await ref
          .read(inventoryRepositoryProvider)
          .renameCategory(summary.category, newName);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Renamed to "$newName" ($count item(s)).')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Rename failed: $error')));
      }
    }
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.summary, required this.onRename});

  final InventoryCategorySummary summary;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.borderSoft),
      ),
      child: ListTile(
        leading: const Icon(Icons.sell_rounded, color: AppPalette.primary),
        title: Text(
          summary.category,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${summary.productCount} item${summary.productCount == 1 ? '' : 's'}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_rounded),
          color: AppPalette.primary,
          onPressed: onRename,
        ),
      ),
    );
  }
}
