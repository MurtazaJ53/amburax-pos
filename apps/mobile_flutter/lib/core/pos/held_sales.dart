import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mobile_models.dart';

/// A parked (suspended) sale — the cart + its discount/customer/date snapshot.
class HeldSale {
  const HeldSale({
    required this.id,
    required this.items,
    required this.discountText,
    required this.discountIsPercent,
    required this.customerName,
    required this.customerPhone,
    required this.saleDate,
    required this.heldAt,
  });

  final String id;
  final List<PosCartItem> items;
  final String discountText;
  final bool discountIsPercent;
  final String customerName;
  final String customerPhone;
  final DateTime? saleDate;
  final DateTime heldAt;

  int get itemCount =>
      items.fold<double>(0, (sum, i) => sum + i.quantity).round();
  double get total => items.fold<double>(0, (sum, i) => sum + i.lineTotal);

  String get label => customerName.trim().isNotEmpty
      ? customerName.trim()
      : '$itemCount item${itemCount == 1 ? '' : 's'}';
}

/// Session store of parked sales so a cashier can suspend a cart, serve the
/// next customer, and resume it. Lives above the POS screen so it survives
/// navigation.
final heldSalesProvider = NotifierProvider<HeldSalesController, List<HeldSale>>(
  HeldSalesController.new,
);

class HeldSalesController extends Notifier<List<HeldSale>> {
  @override
  List<HeldSale> build() => const <HeldSale>[];

  void hold(HeldSale sale) => state = <HeldSale>[...state, sale];

  void remove(String id) =>
      state = state.where((s) => s.id != id).toList(growable: false);
}
