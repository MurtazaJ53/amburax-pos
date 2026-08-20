"use client";

import React, { useState, useMemo } from "react";
import {
  Package,
  Search,
  Plus,
  Edit2,
  AlertTriangle,
  Download,
  X,
  History,
} from "lucide-react";
import { formatCurrency } from "@/lib/utils";
import { useT } from "@/lib/i18n";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



export interface ProductItem {
  id: string;
  shop?: string;
  name: string;
  sku: string;
  barcode?: string;
  category?: string;
  cost_price: number;
  selling_price: number;
  current_stock: number;
  reorder_level: number;
  is_low_stock?: boolean;
  status?: string;
  tax_rate?: number;
  /** How the shop counts this item — "kg", "litre", "piece". Blank for most.
   *  Only meaningful to a shop with weight selling turned on. */
  unit?: string;
  created_at?: string;
  updated_at?: string;
}

/** An inventory row as the API returns it; only the fields read here. */
type ApiInventoryRow = {
  id: string;
  name: string;
  sku?: string;
  barcode?: string;
  category?: string;
  cost_price?: string | null;
  sell_price?: string;
  stock_on_hand?: number;
  gst_rate?: string;
  status?: string;
  hsn_code?: string;
  size?: string;
  description?: string;
  created_at?: string;
  updated_at?: string;
};

interface InventoryManagerProps {
  initialInventory: ApiInventoryRow[];
  initialSummary?: unknown;
  shopId: string;
}

export function InventoryManager({ initialInventory }: InventoryManagerProps) {
  const t = useT();
  const mappedInitial = React.useMemo(() => {
    return (initialInventory ?? []).map((item: ApiInventoryRow) => ({
      id: item.id,
      name: item.name,
      sku: item.sku ?? "",
      barcode: item.barcode || "",
      category: item.category || "General",
      cost_price: parseFloat(item.cost_price || "0"),
      selling_price: parseFloat(item.sell_price || "0"),
      current_stock: item.stock_on_hand || 0,
      reorder_level: 10,
      is_low_stock: (item.stock_on_hand || 0) <= 10,
      tax_rate: parseFloat(item.gst_rate || "5"),
      status: item.status ?? "active",
      created_at: item.created_at || new Date().toISOString(),
      updated_at: item.updated_at || new Date().toISOString(),
    }));
  }, [initialInventory]);

  const [items, setItems] = useState<ProductItem[]>(mappedInitial);
  const [_isLoading, setIsLoading] = useState(false);
  const [_error, setError] = useState<string | null>(null);

  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("all");
  const [onlyLowStock, setOnlyLowStock] = useState(false);

  // Add / Edit Modal state
  const [isProductModalOpen, setIsProductModalOpen] = useState(false);
  const [editingItem, setEditingItem] = useState<ProductItem | null>(null);

  // Form state
  const [formName, setFormName] = useState("");
  const [formSku, setFormSku] = useState("");
  const [formBarcode, setFormBarcode] = useState("");
  const [formCategory, setFormCategory] = useState("Groceries");
  const [formCostPrice, setFormCostPrice] = useState("");
  const [formSellingPrice, setFormSellingPrice] = useState("");
  const [formTaxRate, setFormTaxRate] = useState("5");
  const [formStock, setFormStock] = useState("");
  const [formReorderLevel, setFormReorderLevel] = useState("10");

  // Stock Adjust Modal state
  const [adjustItem, setAdjustItem] = useState<ProductItem | null>(null);
  const [adjustQty, setAdjustQty] = useState("");
  const [adjustType, setAdjustType] = useState<"inward" | "damage" | "correction">("inward");
  const [adjustReason, setAdjustReason] = useState("");

  const fetchItems = async () => {
    try {
      setIsLoading(true);
      const res = await fetch("/api/inventory");
      if (!res.ok) throw new Error("Failed to fetch inventory from server");
      const data = await res.json();
      const mapped = data.map((item: ApiInventoryRow) => ({
        id: item.id,
        name: item.name,
        sku: item.sku ?? "",
        barcode: item.barcode || "",
        category: item.category || "General",
        cost_price: parseFloat(item.cost_price || "0"),
        selling_price: parseFloat(item.sell_price || "0"),
        current_stock: item.stock_on_hand || 0,
        reorder_level: 10,
        is_low_stock: (item.stock_on_hand || 0) <= 10,
        tax_rate: parseFloat(item.gst_rate || "5"),
        status: item.status ?? "active",
        created_at: item.created_at || new Date().toISOString(),
        updated_at: item.updated_at || new Date().toISOString(),
      }));
      setItems(mapped);
    } catch (err) {
      setError(errorMessage(err, "Failed to load inventory"));
    } finally {
      setIsLoading(false);
    }
  };

  const categories = useMemo(() => {
    const list = Array.from(new Set(items.map((i) => i.category).filter((c): c is string => Boolean(c))));
    return ["all", ...list];
  }, [items]);

  const filteredItems = useMemo(() => {
    return items.filter((item) => {
      if (categoryFilter !== "all" && item.category !== categoryFilter) return false;
      if (onlyLowStock && !item.is_low_stock) return false;
      if (search.trim()) {
        const q = search.toLowerCase();
        return (
          item.name.toLowerCase().includes(q) ||
          item.sku.toLowerCase().includes(q) ||
          (item.barcode && item.barcode.includes(q))
        );
      }
      return true;
    });
  }, [items, categoryFilter, onlyLowStock, search]);

  const openAddModal = () => {
    setEditingItem(null);
    setFormName("");
    setFormSku("");
    setFormBarcode("");
    setFormCategory("Groceries");
    setFormCostPrice("");
    setFormSellingPrice("");
    setFormTaxRate("5");
    setFormStock("50");
    setFormReorderLevel("10");
    setIsProductModalOpen(true);
  };

  const openEditModal = (item: ProductItem) => {
    setEditingItem(item);
    setFormName(item.name);
    setFormSku(item.sku);
    setFormBarcode(item.barcode || "");
    setFormCategory(item.category || "Groceries");
    setFormCostPrice(item.cost_price.toString());
    setFormSellingPrice(item.selling_price.toString());
    setFormTaxRate((item.tax_rate ?? 5).toString());
    setFormStock(item.current_stock.toString());
    setFormReorderLevel(item.reorder_level.toString());
    setIsProductModalOpen(true);
  };

  const handleSaveProduct = async (e: React.FormEvent) => {
    e.preventDefault();
    const cost = parseFloat(formCostPrice) || 0;
    const selling = parseFloat(formSellingPrice) || 0;
    const stock = parseInt(formStock) || 0;
    const _reorder = parseInt(formReorderLevel) || 10;
    const tax = parseFloat(formTaxRate) || 0;

    const payload = {
      name: formName,
      sku: formSku || `SKU-${Date.now().toString().slice(-4)}`,
      barcode: formBarcode,
      category: formCategory,
      sell_price: selling.toFixed(2),
      opening_stock: stock,
      cost_price: cost.toFixed(2),
      gst_rate: tax.toFixed(2),
    };

    try {
      if (editingItem) {
        // Edit item on backend
        const res = await fetch(`/api/inventory/${editingItem.id}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            name: formName,
            sku: formSku,
            barcode: formBarcode,
            category: formCategory,
            sell_price: selling.toFixed(2),
            cost_price: cost.toFixed(2),
            gst_rate: tax.toFixed(2),
          }),
        });
        if (!res.ok) {
          const errText = await res.text();
          throw new Error(`Failed to update item: ${errText}`);
        }
      } else {
        // Create item on backend
        const res = await fetch("/api/inventory", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        if (!res.ok) {
          const errText = await res.text();
          throw new Error(`Failed to create item: ${errText}`);
        }
      }
      setIsProductModalOpen(false);
      await fetchItems();
    } catch (err) {
      alert(errorMessage(err, "An error occurred while saving the product"));
    }
  };

  const handleApplyStockAdjustment = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!adjustItem) return;
    const delta = parseInt(adjustQty) || 0;
    const factor = adjustType === "inward" ? 1 : -1;
    const quantityDelta = delta * factor;

    try {
      const res = await fetch(`/api/inventory/${adjustItem.id}/adjust-stock`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          quantity_delta: quantityDelta,
          note: adjustReason || `Manual stock adjustment: ${adjustType}`,
        }),
      });
      if (!res.ok) {
        const errText = await res.text();
        throw new Error(errText || "Failed to adjust stock on backend");
      }
      setAdjustItem(null);
      setAdjustQty("");
      setAdjustReason("");
      await fetchItems();
    } catch (err) {
      alert(errorMessage(err, "An error occurred while adjusting the stock level."));
    }
  };

  // Export CSV
  const handleExportCsv = () => {
    const headers = "Name,SKU,Barcode,Category,Cost Price,Selling Price,Stock,Reorder Level,Tax Rate\n";
    const rows = items
      .map(
        (i) =>
          `"${i.name}","${i.sku}","${i.barcode || ""}","${i.category}",${i.cost_price},${i.selling_price},${i.current_stock},${i.reorder_level},${i.tax_rate}`
      )
      .join("\n");
    const blob = new Blob([headers + rows], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.setAttribute("href", url);
    link.setAttribute("download", `inventory_catalog_${Date.now()}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  return (
    <div className="space-y-6">
      {/* Top Controls & Metrics Strip */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h2 className="text-lg font-bold text-text-primary tracking-tight">
            {t("webInventoryCatalog")}
          </h2>
          <p className="text-xs text-[var(--text-tertiary)]">
            Manage product items, SKU variants, barcodes, GST slabs, and reorder levels
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={handleExportCsv}
            className="flex items-center gap-1.5 px-3 py-2 bg-[var(--surface)] hover:bg-bg-base border border-[var(--border-soft)] text-xs text-[var(--text-secondary)] hover:text-text-primary rounded-xl transition-colors"
          >
            <Download className="w-4 h-4" />
            <span>Export CSV</span>
          </button>

          <button
            onClick={openAddModal}
            className="flex items-center gap-1.5 px-4 py-2 bg-[var(--primary)] hover:bg-[var(--primary-hover)] text-white text-xs font-semibold rounded-xl shadow-md shadow-blue-500/20 transition-all active:scale-95"
          >
            <Plus className="w-4 h-4" />
            <span>Add Product</span>
          </button>
        </div>
      </div>

      {/* Filter & Search Bar */}
      <div className="p-4 bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl flex flex-col md:flex-row items-center gap-3">
        <div className="relative flex-1 w-full">
          <Search className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search by product name, SKU, or barcode..."
            className="w-full pl-10 pr-4 py-2 bg-bg-soft border border-[var(--border-soft)] focus:border-[var(--primary)] rounded-xl text-xs text-text-primary placeholder-[var(--text-tertiary)] outline-none"
          />
        </div>

        <div className="flex items-center gap-3 w-full md:w-auto">
          <select
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
            className="px-3 py-2 bg-bg-soft border border-[var(--border-soft)] text-xs text-text-primary rounded-xl outline-none capitalize"
          >
            {categories.map((c) => (
              <option key={c} value={c} className="capitalize">
                {c === "all" ? "All Categories" : c}
              </option>
            ))}
          </select>

          <button
            onClick={() => setOnlyLowStock(!onlyLowStock)}
            className={`flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-medium border transition-colors shrink-0 ${
              onlyLowStock
                ? "bg-[var(--error)]/20 text-[var(--error)] border-[var(--error)]/30"
                : "bg-bg-soft text-[var(--text-secondary)] border-[var(--border-soft)] hover:text-text-primary"
            }`}
          >
            <AlertTriangle className="w-3.5 h-3.5" />
            <span>Low Stock Only</span>
          </button>
        </div>
      </div>

      {/* High Density Inventory Data Table */}
      <div className="bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl overflow-hidden shadow-xl">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse text-xs">
            <thead>
              <tr className="bg-[var(--bg-soft)] border-b border-[var(--border-soft)] text-[var(--text-tertiary)] font-semibold uppercase tracking-wider text-[10px]">
                <th className="py-3 px-4">Product / SKU</th>
                <th className="py-3 px-4">Category</th>
                <th className="py-3 px-4 text-right">Cost Price</th>
                <th className="py-3 px-4 text-right">Selling Price</th>
                <th className="py-3 px-4 text-center">GST Slab</th>
                <th className="py-3 px-4 text-center">Stock Level</th>
                <th className="py-3 px-4 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--border-soft)]">
              {filteredItems.length === 0 ? (
                <tr>
                  <td colSpan={7} className="py-12 text-center text-[var(--text-tertiary)]">
                    No products found matching your search filters.
                  </td>
                </tr>
              ) : (
                filteredItems.map((item) => (
                  <tr key={item.id} className="hover:bg-bg-base transition-colors">
                    <td className="py-3 px-4">
                      <div className="font-semibold text-text-primary">{item.name}</div>
                      <div className="flex items-center gap-2 text-[10px] text-[var(--text-tertiary)] font-mono mt-0.5">
                        <span>SKU: {item.sku}</span>
                        {item.barcode && <span>• Barcode: {item.barcode}</span>}
                      </div>
                    </td>
                    <td className="py-3 px-4 text-[var(--text-secondary)]">
                      <span className="px-2 py-0.5 rounded-full bg-bg-base border border-[var(--border-soft)] text-[10px]">
                        {item.category || "General"}
                      </span>
                    </td>
                    <td className="py-3 px-4 text-right font-mono text-[var(--text-tertiary)]">
                      {formatCurrency(item.cost_price)}
                    </td>
                    <td className="py-3 px-4 text-right font-mono font-semibold text-text-primary">
                      {formatCurrency(item.selling_price)}
                    </td>
                    <td className="py-3 px-4 text-center">
                      <span className="px-2 py-0.5 rounded text-[10px] font-semibold bg-blue-500/10 text-blue-300 border border-blue-500/20">
                        GST {item.tax_rate ?? 0}%
                      </span>
                    </td>
                    <td className="py-3 px-4 text-center">
                      <div className="inline-flex items-center gap-1.5">
                        <span
                          className={`font-mono font-bold ${
                            item.is_low_stock ? "text-[var(--error)]" : "text-[var(--success)]"
                          }`}
                        >
                          {item.current_stock}
                        </span>
                        {item.is_low_stock && (
                          <span className="px-1.5 py-0.5 text-[9px] font-bold uppercase rounded bg-[var(--error)]/20 text-[var(--error)]">
                            Low
                          </span>
                        )}
                      </div>
                    </td>
                    <td className="py-3 px-4 text-right">
                      <div className="flex items-center justify-end gap-1.5">
                        <button
                          onClick={() => {
                            setAdjustItem(item);
                            setAdjustQty("10");
                            setAdjustType("inward");
                          }}
                          className="px-2.5 py-1 text-[11px] font-medium bg-bg-base hover:bg-[var(--surface)] text-[var(--primary-light)] rounded-lg transition-colors"
                        >
                          {t("webAdjustStock")}
                        </button>
                        <button
                          onClick={() => openEditModal(item)}
                          className="p-1.5 text-[var(--text-tertiary)] hover:text-text-primary hover:bg-bg-base rounded-lg transition-colors"
                          title="Edit product"
                        >
                          <Edit2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* ========================================================= */}
      {/* MODAL: Add / Edit Product                                 */}
      {/* ========================================================= */}
      {isProductModalOpen && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-in fade-in duration-150"
          onClick={() => setIsProductModalOpen(false)}
        >
          <div
            className="w-full max-w-lg bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-[var(--bg-soft)]">
              <div className="flex items-center gap-2">
                <Package className="w-5 h-5 text-[var(--primary-light)]" />
                <span className="font-semibold text-sm text-text-primary">
                  {editingItem ? "Edit Product Details" : "Add New Product to Catalog"}
                </span>
              </div>
              <button
                onClick={() => setIsProductModalOpen(false)}
                className="p-1 rounded-lg text-[var(--text-tertiary)] hover:text-text-primary"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleSaveProduct} className="p-6 space-y-4 overflow-y-auto">
              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Product Name *
                </label>
                <input
                  type="text"
                  required
                  value={formName}
                  onChange={(e) => setFormName(e.target.value)}
                  placeholder="e.g. Organic Mustard Oil 1L"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none focus:border-[var(--primary)]"
                />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    SKU Code
                  </label>
                  <input
                    type="text"
                    value={formSku}
                    onChange={(e) => setFormSku(e.target.value)}
                    placeholder="e.g. OIL-MUST-1L"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Barcode (EAN/UPC)
                  </label>
                  <input
                    type="text"
                    value={formBarcode}
                    onChange={(e) => setFormBarcode(e.target.value)}
                    placeholder="e.g. 8901234567890"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    {t("webCategory")}
                  </label>
                  <input
                    type="text"
                    value={formCategory}
                    onChange={(e) => setFormCategory(e.target.value)}
                    placeholder="e.g. Groceries"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    GST Tax Slab
                  </label>
                  <select
                    value={formTaxRate}
                    onChange={(e) => setFormTaxRate(e.target.value)}
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  >
                    <option value="0">0% (Nil / Exempt)</option>
                    <option value="5">5% (Essential Goods)</option>
                    <option value="12">12% (Standard 1)</option>
                    <option value="18">18% (Standard 2)</option>
                    <option value="28">28% (Luxury / Aerated)</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Cost / Buying Price (₹) *
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    required
                    value={formCostPrice}
                    onChange={(e) => setFormCostPrice(e.target.value)}
                    placeholder="120.00"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Selling Price (₹) *
                  </label>
                  <input
                    type="number"
                    step="0.01"
                    required
                    value={formSellingPrice}
                    onChange={(e) => setFormSellingPrice(e.target.value)}
                    placeholder="150.00"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Current Stock (Units)
                  </label>
                  <input
                    type="number"
                    value={formStock}
                    onChange={(e) => setFormStock(e.target.value)}
                    placeholder="50"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                    Reorder Alert Level
                  </label>
                  <input
                    type="number"
                    value={formReorderLevel}
                    onChange={(e) => setFormReorderLevel(e.target.value)}
                    placeholder="10"
                    className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                  />
                </div>
              </div>

              <div className="pt-4 border-t border-[var(--border-soft)] flex items-center justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setIsProductModalOpen(false)}
                  className="px-4 py-2 text-xs font-medium text-[var(--text-secondary)] hover:text-text-primary bg-bg-base rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-5 py-2 text-xs font-semibold text-white bg-[var(--primary)] hover:bg-[var(--primary-hover)] rounded-xl shadow-md shadow-blue-500/20"
                >
                  Save Product
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* ========================================================= */}
      {/* MODAL: Stock Adjustment                                   */}
      {/* ========================================================= */}
      {adjustItem && (
        <div
          role="dialog"
          aria-modal="true"
          className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-in fade-in duration-150"
          onClick={() => setAdjustItem(null)}
        >
          <div
            className="w-full max-w-md bg-[var(--surface)] border border-[var(--border)] rounded-2xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-[var(--bg-soft)]">
              <div className="flex items-center gap-2">
                <History className="w-5 h-5 text-[var(--primary-light)]" />
                <span className="font-semibold text-sm text-text-primary">Stock Adjustment</span>
              </div>
              <button
                onClick={() => setAdjustItem(null)}
                className="p-1 text-[var(--text-tertiary)] hover:text-text-primary"
              >
                <X className="w-4 h-4" />
              </button>
            </div>

            <form onSubmit={handleApplyStockAdjustment} className="p-6 space-y-4">
              <div className="p-3 rounded-xl bg-bg-soft border border-[var(--border-soft)]">
                <div className="font-semibold text-xs text-text-primary">{adjustItem.name}</div>
                <div className="text-[11px] text-[var(--text-tertiary)] mt-0.5">
                  Current Stock: <strong>{adjustItem.current_stock} units</strong>
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  {t("webAdjustmentType")}
                </label>
                <select
                  value={adjustType}
                  onChange={(e) => setAdjustType(e.target.value as "inward" | "damage" | "correction")}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                >
                  <option value="inward">Inward Delivery / Stock In (+)</option>
                  <option value="damage">Damage / Spoilage Out (-)</option>
                  <option value="correction">Inventory Audit Correction (-)</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Quantity Units
                </label>
                <input
                  type="number"
                  min="1"
                  required
                  value={adjustQty}
                  onChange={(e) => setAdjustQty(e.target.value)}
                  placeholder="10"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  Adjustment Reason / Note
                </label>
                <input
                  type="text"
                  value={adjustReason}
                  onChange={(e) => setAdjustReason(e.target.value)}
                  placeholder="e.g. Received from Supplier Po #41"
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
              </div>

              <div className="pt-3 border-t border-[var(--border-soft)] flex items-center justify-end gap-3">
                <button
                  type="button"
                  onClick={() => setAdjustItem(null)}
                  className="px-4 py-2 text-xs text-[var(--text-secondary)] hover:text-text-primary bg-bg-base rounded-xl"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  className="px-5 py-2 text-xs font-semibold text-white bg-[var(--primary)] hover:bg-[var(--primary-hover)] rounded-xl shadow-md"
                >
                  {t("webConfirmAdjustment")}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
