"use client";

import React, { useEffect, useState, useMemo } from "react";
import {
  Package,
  Search,
  Plus,
  Edit2,
  Download,
  X,
  ChevronDown,
  LayoutGrid,
  Rows3,
  History,
  ImagePlus,
} from "lucide-react";
import { formatCurrency, formatQuantity } from "@/lib/utils";
import { useT } from "@/lib/i18n";
import { fileToProductImage, formatBytes, dataUriBytes } from "@/lib/product-image";
import {
  averageMargin,
  DEFAULT_REORDER_LEVEL,
  mapInventoryRow,
  marginPercent,
  stockFillPercent,
} from "@/lib/inventory-rows";
import type { ApiInventoryRow, ProductRow } from "@/lib/inventory-rows";
import {
  applyFilters,
  DEFAULT_FILTERS,
  categoryFacets,
  hasActiveFilters,
  stockFacets,
} from "@/lib/inventory-filters";
import type { SortKey, StockFilter } from "@/lib/inventory-filters";
import { useServerRefresh } from "@/lib/use-server-refresh";
import { useDialog } from "@/components/ui/dialog-provider";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}



/** Business types whose prices are quoted BEFORE tax.
 *
 *  Wholesale and service sell B2B, where the buyer reclaims the GST as input
 *  credit and therefore negotiates on the pre-tax rate. Retail, grocery and
 *  the rest price at MRP, which is inclusive of all taxes by law — selling
 *  above it is an offence quite apart from GST.
 *
 *  A DEFAULT only. It seeds the control for a new product and never overrides
 *  what a shopkeeper chose, and never touches an existing item.
 */
const TAX_EXCLUSIVE_BUSINESS_TYPES = ["wholesale", "service"];

/** The row shape the screen draws. Defined in lib/inventory-rows.ts so the
 *  mapping from the API can be unit tested; aliased here because the modals
 *  and handlers below all refer to it by this name. */
export type ProductItem = ProductRow;

interface InventoryManagerProps {
  initialInventory: ApiInventoryRow[];
  initialSummary?: unknown;
  shopId: string;
  /** Whether this member's role permits seeing cost prices at all. Without
   *  it the screen cannot tell "no cost recorded" from "not your business",
   *  since the server sends null for both. */
  canViewCosts?: boolean;
}

/** A heading inside a long form.
 *
 *  This one asks for twelve things in a scrolling box, and it used to be a
 *  flat list of them. Scrolling had nothing to orient by, so a label caught
 *  half-way under the header read as a broken screen rather than as the top
 *  of a section - which is exactly what a shopkeeper reported.
 *
 *  Three groups, each answering a different question: what the thing is, what
 *  it costs, and how many there are.
 */
function FormSection({ title, hint }: { title: string; hint: string }) {
  return (
    <div className="border-t border-[var(--border-soft)] pt-4 first:border-0 first:pt-0">
      <p className="m-0 font-mono text-[10px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
        {title}
      </p>
      <p className="m-0 mt-0.5 text-[11.5px] font-semibold text-[var(--text-tertiary)]">
        {hint}
      </p>
    </div>
  );
}

export function InventoryManager({ initialInventory, canViewCosts = false }: InventoryManagerProps) {
  const { say } = useDialog();
  const refreshServerData = useServerRefresh();
  const t = useT();
  const mappedInitial = React.useMemo(
    () => (initialInventory ?? []).map(mapInventoryRow),
    [initialInventory],
  );

  const [items, setItems] = useState<ProductItem[]>(mappedInitial);
  const [_isLoading, setIsLoading] = useState(false);
  const [_error, setError] = useState<string | null>(null);

  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("all");
  /** Which slice of the catalogue is on screen. The old lone "low stock
   *  only" toggle could not express "show me what has actually run out",
   *  which is the one a shopkeeper needs before ordering. */
  const [stockFilter, setStockFilter] = useState<StockFilter>("all");
  const [sort, setSort] = useState<SortKey>("name");
  /** Cards fit roughly five times as many products on a screen as rows do,
   *  which is what you want when you are looking FOR something. The table
   *  stays for reading figures across columns. */
  const [view, setView] = useState<"grid" | "table">("grid");
  /** The category band is a whole row of chrome above the products. It earns
   *  its place while you are choosing, not for the rest of the time. */
  const [showCategories, setShowCategories] = useState(false);

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
  //: HSN/SAC. Mandatory on a GST invoice, and the web form had no input for it
  //: at all — the Flutter app has had one all along, so the same catalogue had
  //: HSN codes or not depending on which device typed the product in.
  const [formHsnCode, setFormHsnCode] = useState("");
  /** The product photo as a small data URI, or "" for none. */
  const [formImage, setFormImage] = useState("");
  /** Whether the picture was changed in this editing session.
   *
   *  The photo is no longer sent back with the product, so the form cannot
   *  hold the current one. Posting formImage regardless would send an empty
   *  string every time, and an empty string means "clear it" - so correcting
   *  a price would silently delete the photo. It is sent only when touched. */
  const [imageDirty, setImageDirty] = useState(false);
  /** Shown while editing, so the existing photo is visible without the form
   *  holding its bytes. */
  const [existingImageId, setExistingImageId] = useState<string | null>(null);
  const [imageBusy, setImageBusy] = useState(false);
  const [imageError, setImageError] = useState("");
  //: Whether the selling price already contains the GST.
  //:
  //: The form set a GST slab and never asked this, so every web-created
  //: product silently took the model default (true). The Flutter app HAS the
  //: switch, which is worse than uniformly missing: two items on the same
  //: shelf could mean different things depending on where they were entered.
  const [formPriceIncludesTax, setFormPriceIncludesTax] = useState(true);
  //: The shop default, from its business type. Wholesale and service quote
  //: pre-tax because the buyer reclaims the GST as input credit; retail prices
  //: are MRP, which is inclusive by law.
  const [defaultIncludesTax, setDefaultIncludesTax] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/settings");
        if (!res.ok) return;
        const data = await res.json();
        if (cancelled) return;
        const businessType = String(data?.business_type ?? "retail");
        setDefaultIncludesTax(!TAX_EXCLUSIVE_BUSINESS_TYPES.includes(businessType));
      } catch {
        // Falls back to inclusive, which is right for the retail majority.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // Stock Adjust Modal state
  const [adjustItem, setAdjustItem] = useState<ProductItem | null>(null);
  const [adjustQty, setAdjustQty] = useState("");
  const [adjustType, setAdjustType] = useState<"inward" | "damage" | "correction">("inward");
  const [adjustReason, setAdjustReason] = useState("");

  /** The cursor for the next page, or null when the catalogue is exhausted.
   *
   *  The list used to stop dead at five hundred products with nothing to say
   *  about it. It is keyset-paged now, and this is how the screen knows there
   *  is more to fetch. */
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);

  const PAGE_SIZE = 100;

  /** One page of products. `cursor` null means start again from the top. */
  const fetchPage = async (cursor: string | null) => {
    const params = new URLSearchParams({ limit: String(PAGE_SIZE) });
    if (cursor) params.set("cursor", cursor);
    const res = await fetch(`/api/inventory?${params.toString()}`);
    if (!res.ok) throw new Error("Failed to fetch inventory from server");
    const rows = await res.json();
    return {
      items: (rows as ApiInventoryRow[]).map(mapInventoryRow),
      cursor: res.headers.get("X-Next-Cursor"),
    };
  };

  const fetchItems = async () => {
    try {
      setIsLoading(true);
      const page = await fetchPage(null);
      setItems(page.items);
      setNextCursor(page.cursor);
    } catch (err) {
      setError(errorMessage(err, "Failed to load inventory"));
    } finally {
      setIsLoading(false);
    }
  };

  const loadMore = async () => {
    if (!nextCursor || loadingMore) return;
    setLoadingMore(true);
    try {
      const page = await fetchPage(nextCursor);
      // Appended by id, because a product edited in another tab between two
      // pages would otherwise appear twice.
      setItems((previous) => {
        const seen = new Set(previous.map((item) => item.id));
        return [...previous, ...page.items.filter((item) => !seen.has(item.id))];
      });
      setNextCursor(page.cursor);
    } catch (err) {
      setError(errorMessage(err, "Could not load more products."));
    } finally {
      setLoadingMore(false);
    }
  };

  /** Options for the jump-to-category select. Built from the same facets the
   *  chips use, alphabetically here because a menu is scanned by name — and
   *  crucially including the uncategorised bucket, so a value picked from the
   *  chips can never leave this select showing blank. */
  const categories = useMemo(() => {
    const names = categoryFacets(items)
      .map((facet) => facet.key)
      .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }));
    return ["all", ...names];
  }, [items]);

  const filterState = useMemo(
    () => ({ search, category: categoryFilter, stock: stockFilter, sort }),
    [search, categoryFilter, stockFilter, sort],
  );

  const filteredItems = useMemo(
    () => applyFilters(items, filterState),
    [items, filterState],
  );

  const filtersActive = hasActiveFilters(filterState);

  /** Counts for the filter chips. A chip that says "Out of stock 3" answers
   *  the question as well as filtering by it; the old toggle made you click
   *  to find out whether it mattered. */
  /** Chip counts are faceted: each row of chips is narrowed by the OTHER
   *  controls but not by itself. Global counts start lying the moment a
   *  category is chosen - the chip promises 144 out of stock and the table
   *  shows nine. */
  const counts = useMemo(
    () => stockFacets(items, categoryFilter, search),
    [items, categoryFilter, search],
  );

  const categoryChips = useMemo(
    () => categoryFacets(items, stockFilter, search),
    [items, stockFilter, search],
  );

  /** Retail value of everything on the shelf, and what it cost, when the
   *  viewer is allowed to know. */
  const totals = useMemo(() => {
    const retail = items.reduce((sum, i) => sum + i.selling_price * i.current_stock, 0);
    const priced = items.filter((i) => i.cost_price !== null);
    const cost = priced.reduce((sum, i) => sum + (i.cost_price ?? 0) * i.current_stock, 0);
    return { retail, cost, costIsPartial: priced.length < items.length };
  }, [items]);

  const avgMargin = useMemo(() => averageMargin(items), [items]);

  /** The slices worth a one-click jump. "No cost price" only appears for a
   *  role allowed to see costs at all — for anyone else the server sends the
   *  same null, and the chip would be nagging them about hidden data. */
  const stockChips = useMemo(
    () => [
      { key: "all" as StockFilter, label: "All", count: counts.all, tone: "neutral" as const },
      { key: "in" as StockFilter, label: "In stock", count: counts.in, tone: "good" as const },
      { key: "out" as StockFilter, label: "Out of stock", count: counts.out, tone: "urgent" as const },
      // The counterpart to letting the POS sell past zero. Overselling is
      // allowed because a customer with cash beats a number in a database —
      // but only if the items it happened to land on a list someone works
      // through. This is that list.
      {
        key: "oversold" as StockFilter,
        label: "Short",
        count: counts.oversold,
        tone: "urgent" as const,
      },
      // The other half of the zero-stock population, and a different job:
      // these are not shortfalls to investigate, they are items that were
      // imported or added without ever being given a quantity. Counting them
      // in with real shortfalls would bury the handful that matter.
      {
        key: "untracked" as StockFilter,
        label: "Stock not tracked",
        count: counts.untracked,
        tone: "warn" as const,
      },
      { key: "low" as StockFilter, label: "Low", count: counts.low, tone: "warn" as const },
      // Data-quality slices. These are not "what do I reorder" — they are
      // "what will bite me": an item the counter cannot scan, and an item
      // that will fail a GST return.
      {
        key: "nobarcode" as StockFilter,
        label: "No barcode",
        count: counts.nobarcode,
        tone: "warn" as const,
      },
      {
        key: "nohsn" as StockFilter,
        label: "No HSN",
        count: counts.nohsn,
        tone: "warn" as const,
      },
      ...(canViewCosts
        ? [
            {
              key: "nocost" as StockFilter,
              label: "No cost price",
              count: counts.nocost,
              tone: "warn" as const,
            },
          ]
        : []),
    ],
    [counts, canViewCosts],
  );

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
    setFormHsnCode("");
    setFormImage("");
    setImageDirty(false);
    setExistingImageId(null);
    setImageError("");
    setFormPriceIncludesTax(defaultIncludesTax);
    setIsProductModalOpen(true);
  };

  const openEditModal = (item: ProductItem) => {
    setEditingItem(item);
    setFormName(item.name);
    setFormSku(item.sku);
    setFormBarcode(item.barcode || "");
    setFormCategory(item.category || "Groceries");
    // An unknown cost opens the field empty, not as "0" — typing over a
    // pre-filled zero is how a wrong cost gets saved by accident.
    setFormCostPrice(item.cost_price === null ? "" : item.cost_price.toString());
    setFormSellingPrice(item.selling_price.toString());
    setFormTaxRate((item.tax_rate ?? 5).toString());
    setFormStock(item.current_stock.toString());
    setFormReorderLevel((item.reorder_level ?? DEFAULT_REORDER_LEVEL).toString());
    setFormHsnCode(item.hsn_code || "");
    // The list no longer carries the picture, so the preview points at the
    // image endpoint instead of holding its bytes.
    setFormImage("");
    setImageDirty(false);
    setExistingImageId(item.has_image ? item.id : null);
    setImageError("");
    // The item's own answer, never the shop default — editing a product must
    // not silently re-base its price.
    setFormPriceIncludesTax(item.price_includes_tax ?? true);
    setIsProductModalOpen(true);
  };

  // Guards both modals against a second click landing before the first request
  // returns. Neither had one, so a double-tap — easy on a slow connection or a
  // POS touchscreen — created a duplicate product, or applied a +10 stock
  // adjustment twice as +20. Every other manager in this codebase already had
  // this; inventory was the gap.
  const [isSubmitting, setIsSubmitting] = useState(false);

  /** Takes a file from the picker, shrinks it, and keeps the result in state.
   *  Nothing is uploaded separately — the photo travels with the product save,
   *  because image_data is a column on the item, not a file somewhere else. */
  const handlePickImage = async (file: File | undefined) => {
    if (!file) return;
    setImageBusy(true);
    setImageError("");
    try {
      setFormImage(await fileToProductImage(file));
      setImageDirty(true);
      // A newly chosen picture replaces whatever was stored, so the old one
      // stops being the thing on screen.
      setExistingImageId(null);
    } catch (err) {
      setImageError(
        err instanceof Error ? err.message : "That image could not be used.",
      );
    } finally {
      setImageBusy(false);
    }
  };

  const handleSaveProduct = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isSubmitting) return;
    setIsSubmitting(true);
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
      private_cost_price: cost.toFixed(2),
      gst_rate: tax.toFixed(2),
      hsn_code: formHsnCode.trim(),
      price_includes_tax: formPriceIncludesTax,
      ...(imageDirty ? { image_data: formImage } : {}),
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
            private_cost_price: cost.toFixed(2),
            gst_rate: tax.toFixed(2),
            hsn_code: formHsnCode.trim(),
            price_includes_tax: formPriceIncludesTax,
            ...(imageDirty ? { image_data: formImage } : {}),
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
      refreshServerData();
    } catch (err) {
      say("Could not save this product", errorMessage(err, "Something went wrong saving it."), "danger");
    } finally {
      // In a finally, not after the happy path: several branches above return
      // early, and a stuck flag would leave the form permanently dead.
      setIsSubmitting(false);
    }
  };

  const handleApplyStockAdjustment = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!adjustItem || isSubmitting) return;
    setIsSubmitting(true);
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
      refreshServerData();
    } catch (err) {
      say("Could not adjust the stock", errorMessage(err, "Something went wrong."), "danger");
    } finally {
      setIsSubmitting(false);
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
    // The figures and the filters hold still; only the rows move. Two hundred
    // items used to scroll the counts and the search box off the top, so you
    // reached the bottom of the list with nothing left to filter by.
    <div className="flex min-h-0 flex-1 flex-col gap-5">
      {/* One row: figures on the left, actions on the right, never wrapping
          into a second line of empty space. Each figure is a labelled unit
          with a rule between, so four numbers read as four things rather
          than one run-on sentence. */}
      <div className="flex items-center gap-4 rounded-[14px] border border-[var(--border-soft)] bg-[var(--surface)] px-4 py-2.5 shadow-sm animate-fade-in-up">
        <dl className="no-scrollbar m-0 flex min-w-0 flex-1 items-stretch gap-4 overflow-x-auto">
          {[
            {
              value: String(items.length),
              label: "items",
              detail: `${Math.max(categories.length - 1, 0)} categories`,
              tone: "text-[var(--text-primary)]",
            },
            {
              value: String(counts.out + counts.low),
              label: "need restock",
              detail: counts.out > 0 ? `${counts.out} out of stock` : "none out of stock",
              tone:
                counts.out + counts.low > 0
                  ? "text-[var(--error-strong)]"
                  : "text-[var(--success-strong)]",
            },
            {
              value: formatCurrency(totals.retail),
              label: "stock value",
              detail: canViewCosts ? `${formatCurrency(totals.cost)} at cost` : "at selling price",
              tone: "text-[var(--text-primary)]",
            },
            ...(canViewCosts
              ? [
                  {
                    value: avgMargin === null ? "—" : `${avgMargin.toFixed(1)}%`,
                    label: "avg margin",
                    detail:
                      counts.nocost > 0 ? `${counts.nocost} without cost` : "across every item",
                    tone: "text-[var(--text-primary)]",
                  },
                ]
              : []),
          ].map((stat, index) => (
            <div
              key={stat.label}
              className={`flex shrink-0 flex-col justify-center ${
                index > 0 ? "border-l border-[var(--border-soft)] pl-4" : ""
              }`}
            >
              <dt className="font-mono text-[9.5px] font-bold uppercase tracking-[0.14em] text-[var(--text-tertiary)]">
                {stat.label}
              </dt>
              <dd className="m-0 flex items-baseline gap-1.5">
                <span className={`tnum font-mono text-[17px] font-bold leading-tight ${stat.tone}`}>
                  {stat.value}
                </span>
                <span className="whitespace-nowrap text-[11px] font-semibold text-[var(--text-tertiary)]">
                  {stat.detail}
                </span>
              </dd>
            </div>
          ))}
        </dl>

        <div className="flex shrink-0 gap-2">
          <button
            onClick={handleExportCsv}
            className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2 text-[12px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]"
          >
            <Download className="h-3.5 w-3.5" />
            <span className="hidden lg:inline">Export</span>
          </button>
          <button
            onClick={openAddModal}
            className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3.5 py-2 text-[12px] font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20"
          >
            <Plus className="h-4 w-4" />
            Add product
          </button>
        </div>
      </div>

      {/* Find, narrow, order.
          One row for the two controls that take a value, one for the slices
          worth a single click. Splitting them keeps the chips on a line of
          their own so they never reflow around a growing search box, and it
          separates "which rows" from "what order". */}
      <div className="flex flex-col gap-2.5 rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] p-3 shadow-sm animate-fade-in-up delay-2">
        <div className="flex flex-wrap items-center gap-2.5">
          <div className="relative min-w-[220px] flex-1">
            <Search className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--text-tertiary)]" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search by name, SKU, or scan a barcode..."
              aria-label="Search products"
              className="w-full rounded-[10px] border border-[var(--border-soft)] bg-[var(--bg-soft)] py-2.5 pl-10 pr-9 text-[12.5px] font-medium text-[var(--text-primary)] outline-none transition-colors placeholder:text-[var(--text-tertiary)] focus:border-[var(--primary)]"
            />
            {search && (
              <button
                type="button"
                onClick={() => setSearch("")}
                aria-label="Clear search"
                className="focus-ring absolute right-2 top-1/2 grid h-6 w-6 -translate-y-1/2 cursor-pointer place-items-center rounded-full text-[var(--text-tertiary)] transition-colors hover:bg-[var(--bg-base)] hover:text-[var(--text-primary)]"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            )}
          </div>

          <label className="flex items-center gap-2">
            <span className="sr-only">Filter by category</span>
            <select
              value={categoryFilter}
              onChange={(e) => setCategoryFilter(e.target.value)}
              className="focus-ring cursor-pointer rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2.5 text-[12.5px] font-bold capitalize text-[var(--text-secondary)] outline-none transition-colors hover:border-[var(--border)]"
            >
              {categories.map((c) => (
                <option key={c} value={c} className="capitalize">
                  {c === "all" ? "All categories" : c}
                </option>
              ))}
            </select>
          </label>

          {/* Cards or rows. Kept beside the sort because both change how the
              same set is presented rather than which set it is. */}
          <div className="flex shrink-0 items-center gap-1 rounded-[10px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-1">
            {[
              { key: "grid" as const, label: "Cards", Icon: LayoutGrid },
              { key: "table" as const, label: "Rows", Icon: Rows3 },
            ].map(({ key, label, Icon }) => (
              <button
                key={key}
                type="button"
                onClick={() => setView(key)}
                aria-pressed={view === key}
                title={label}
                className={`focus-ring grid h-7 w-7 cursor-pointer place-items-center rounded-[7px] transition-colors ${
                  view === key
                    ? "bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                    : "text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
                }`}
              >
                <Icon className="h-3.5 w-3.5" />
                <span className="sr-only">{label}</span>
              </button>
            ))}
          </div>

          {/* Ordering is not filtering: it hides nothing, so it sits apart
              from the chips and never lights up as an active filter. */}
          <label className="flex items-center gap-2">
            <span className="font-mono text-[9.5px] font-bold uppercase tracking-[0.13em] text-[var(--text-tertiary)]">
              Sort
            </span>
            <select
              value={sort}
              onChange={(e) => setSort(e.target.value as SortKey)}
              aria-label="Sort products"
              className="focus-ring cursor-pointer rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2.5 text-[12.5px] font-bold text-[var(--text-secondary)] outline-none transition-colors hover:border-[var(--border)]"
            >
              <option value="name">Name A-Z</option>
              <option value="stock-low">Emptiest shelf first</option>
              <option value="value-high">Most money on the shelf</option>
              {canViewCosts && <option value="margin-low">Thinnest margin first</option>}
              <option value="recent">Recently updated</option>
            </select>
          </label>

          {/* A divider rather than a whole band. The category label and the
              slices each sat on a row of their own, which cost the products
              two lines of screen for controls that fit beside the others. */}
          <span
            aria-hidden="true"
            className="hidden h-6 w-px shrink-0 bg-[var(--border-soft)] lg:block"
          />

          <button
            type="button"
            onClick={() => setShowCategories((open) => !open)}
            aria-expanded={showCategories}
            className="focus-ring flex shrink-0 cursor-pointer items-center gap-1 rounded-[8px] px-1.5 py-1 font-mono text-[9.5px] font-bold uppercase tracking-[0.13em] text-[var(--text-tertiary)] transition-colors hover:text-[var(--text-primary)]"
          >
            {categoryFilter === "all" ? "Category" : categoryFilter}
            <ChevronDown
              className={`h-3 w-3 transition-transform duration-200 ${
                showCategories ? "rotate-180" : ""
              }`}
            />
          </button>
        </div>

        {/* Only this expands, and only while a category is being chosen. */}
        {showCategories && (
          <div className="no-scrollbar mt-2.5 flex items-center gap-2 overflow-x-auto border-t border-[var(--border-soft)] pt-2.5">
            <button
              type="button"
              onClick={() => setCategoryFilter("all")}
              aria-pressed={categoryFilter === "all"}
              className={`focus-ring shrink-0 cursor-pointer whitespace-nowrap rounded-full border px-3.5 py-2 text-[11.5px] font-bold transition-colors ${
                categoryFilter === "all"
                  ? "border-[var(--primary)] bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                  : "border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
              }`}
            >
              All <span className="tnum font-mono">{counts.all}</span>
            </button>
            {categoryChips.map((facet) => {
              const active = categoryFilter === facet.key;
              return (
                <button
                  key={facet.key}
                  type="button"
                  onClick={() => setCategoryFilter(active ? "all" : facet.key)}
                  aria-pressed={active}
                  className={`focus-ring shrink-0 cursor-pointer whitespace-nowrap rounded-full border px-3.5 py-2 text-[11.5px] font-bold capitalize transition-colors ${
                    active
                      ? "border-[var(--primary)] bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                      : "border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] hover:border-[var(--border)] hover:text-[var(--text-primary)]"
                  }`}
                >
                  {facet.label} <span className="tnum font-mono">{facet.count}</span>
                </button>
              );
            })}
          </div>
        )}

        <div className="mt-2.5 flex items-center gap-2 border-t border-[var(--border-soft)] pt-2.5">
          <div className="no-scrollbar flex min-w-0 flex-1 items-center gap-2 overflow-x-auto">
            {stockChips.map((chip) => {
              const active = stockFilter === chip.key;
              // Never disable the chip that is currently on: faceting can drop
              // its count to zero, and a disabled active filter is a trap with
              // no way back to the full list.
              const empty = chip.count === 0 && chip.key !== "all" && !active;
              return (
                <button
                  key={chip.key}
                  onClick={() => setStockFilter(chip.key)}
                  aria-pressed={active}
                  disabled={empty}
                  className={`focus-ring shrink-0 whitespace-nowrap rounded-full border px-3.5 py-2 text-[11.5px] font-bold transition-colors ${
                    empty
                      ? "cursor-not-allowed border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-tertiary)] opacity-60"
                      : active
                        ? "cursor-pointer border-[var(--primary)] bg-[var(--primary)]/12 text-[var(--primary-dark)]"
                        : chip.tone === "urgent"
                          ? "cursor-pointer border-[var(--error)]/30 bg-[var(--error)]/10 text-[var(--error-strong)] hover:bg-[var(--error)]/16"
                          : chip.tone === "warn"
                            ? "cursor-pointer border-[var(--warning)]/35 bg-[var(--warning)]/10 text-[var(--warning-strong)] hover:bg-[var(--warning)]/18"
                            : chip.tone === "good"
                              ? "cursor-pointer border-[var(--success)]/30 bg-[var(--success)]/10 text-[var(--success-strong)] hover:bg-[var(--success)]/16"
                              : "cursor-pointer border-[var(--border-soft)] bg-[var(--surface)] text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                  }`}
                >
                  {chip.label} <span className="tnum font-mono">{chip.count}</span>
                </button>
              );
            })}
          </div>

          {filtersActive && (
            <button
              type="button"
              onClick={() => {
                setSearch(DEFAULT_FILTERS.search);
                setCategoryFilter(DEFAULT_FILTERS.category);
                setStockFilter(DEFAULT_FILTERS.stock);
              }}
              className="focus-ring shrink-0 cursor-pointer whitespace-nowrap rounded-full border border-[var(--border-soft)] bg-[var(--surface)] px-3.5 py-2 text-[11.5px] font-bold text-[var(--text-secondary)] transition-colors hover:border-[var(--primary)] hover:text-[var(--primary-dark)]"
            >
              Clear filters
            </button>
          )}
        </div>
      </div>

      {/* The catalogue */}
      <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-[16px] border border-[var(--border-soft)] bg-[var(--surface)] shadow-sm animate-fade-in-up delay-3">
        {view === "grid" ? (
          <div className="no-scrollbar min-h-0 flex-1 overflow-auto p-3">
            {filteredItems.length === 0 ? (
              <p className="px-4 py-14 text-center text-xs font-bold text-[var(--text-tertiary)]">
                No products match these filters.
              </p>
            ) : (
              <ul className="m-0 grid list-none gap-2 p-0 [grid-template-columns:repeat(auto-fill,minmax(168px,1fr))]">
                {filteredItems.map((item, index) => {
                  const margin = marginPercent(item);
                  return (
                    <li
                      key={item.id}
                      className="animate-fade-in-up"
                      style={{ animationDelay: `${Math.min(index, 12) * 25}ms` }}
                    >
                      <button
                        type="button"
                        onClick={() => openEditModal(item)}
                        className="focus-ring hover-nudge group flex h-full w-full cursor-pointer flex-col overflow-hidden rounded-[13px] border border-[var(--border-soft)] bg-[var(--surface)] text-left transition-colors hover:border-[var(--primary)]"
                      >
                        <span className="relative block aspect-[4/3] w-full overflow-hidden border-b border-[var(--border-soft)] bg-[var(--bg-soft)]">
                          {item.has_image ? (
                            // eslint-disable-next-line @next/next/no-img-element
                            <img
                              src={`/api/inventory/${item.id}/image`}
                              alt=""
                              loading="lazy"
                              className="h-full w-full object-cover"
                            />
                          ) : (
                            <span className="grid h-full w-full place-items-center bg-gradient-to-br from-[var(--primary)]/10 to-[var(--bg-soft)] text-[26px] font-extrabold text-[var(--primary-hover)] opacity-55">
                              {item.name.trim().charAt(0).toUpperCase()}
                            </span>
                          )}

                          {/* State on the picture, in words as well as colour,
                              and nothing at all for an item nobody ever
                              counted - its number is not a claim. */}
                          {!item.is_tracked ? null : item.current_stock < 0 ? (
                            <span className="absolute left-1.5 top-1.5 rounded-full bg-[var(--error)] px-2 py-0.5 text-[9.5px] font-extrabold text-white">
                              Short {formatQuantity(Math.abs(item.current_stock))}
                            </span>
                          ) : item.is_out_of_stock ? (
                            <span className="absolute left-1.5 top-1.5 rounded-full bg-[var(--warning)] px-2 py-0.5 text-[9.5px] font-extrabold text-white">
                              Shelf empty
                            </span>
                          ) : item.is_low_stock ? (
                            <span className="absolute left-1.5 top-1.5 rounded-full bg-[var(--warning)] px-2 py-0.5 text-[9.5px] font-extrabold text-white">
                              {formatQuantity(item.current_stock)} left
                            </span>
                          ) : null}

                          {canViewCosts && item.cost_price === null && (
                            <span className="absolute right-1.5 top-1.5 rounded-full bg-[var(--surface)]/90 px-2 py-0.5 text-[9.5px] font-extrabold text-[var(--warning-strong)]">
                              No cost
                            </span>
                          )}
                        </span>

                        <span className="flex flex-1 flex-col gap-0.5 px-2.5 pb-2.5 pt-2">
                          <span className="line-clamp-2 text-[12.5px] font-extrabold leading-snug text-[var(--text-primary)] group-hover:text-[var(--primary-hover)]">
                            {item.name}
                          </span>
                          <span className="truncate font-mono text-[10px] font-semibold text-[var(--text-tertiary)]">
                            {item.category || "Uncategorised"}
                            {item.sku ? ` · ${item.sku}` : ""}
                          </span>

                          <span className="mt-auto flex items-baseline justify-between gap-2 pt-1.5">
                            <b className="tnum font-mono text-[14.5px] font-bold tracking-tight text-[var(--text-primary)]">
                              {formatCurrency(item.selling_price)}
                            </b>
                            {canViewCosts && margin !== null && (
                              <span
                                className={`tnum font-mono text-[11px] font-bold ${
                                  margin < 10
                                    ? "text-[var(--error-strong)]"
                                    : margin < 25
                                      ? "text-[var(--warning-strong)]"
                                      : "text-[var(--success-strong)]"
                                }`}
                              >
                                {margin.toFixed(0)}%
                              </span>
                            )}
                          </span>

                          <span className="tnum font-mono text-[10px] font-semibold text-[var(--text-tertiary)]">
                            {!item.is_tracked
                              ? "stock not tracked"
                              : `${formatQuantity(item.current_stock)} in stock`}
                          </span>
                        </span>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        ) : (
          // The scroll container and the table are separate on purpose:
          // giving one element the flex sizing AND the scrolling collapses
          // its rows to nothing.
          <div className="min-h-0 flex-1 overflow-auto">
          <table className="w-full border-collapse text-left">
            {/* Pinned, so you still know which column is Cost and which is
                Selling a hundred rows down. */}
            <thead className="sticky top-0 z-10">
              <tr className="border-b border-[var(--border-soft)] bg-[var(--bg-soft)] font-mono text-[9.5px] font-semibold uppercase tracking-[0.13em] text-[var(--text-tertiary)]">
                <th className="px-4 py-2.5">Product / SKU</th>
                <th className="px-4 py-2.5">Category</th>
                {canViewCosts && <th className="px-4 py-2.5 text-right">Cost</th>}
                <th className="px-4 py-2.5 text-right">Selling</th>
                {canViewCosts && <th className="px-4 py-2.5 text-right">Margin</th>}
                <th className="px-4 py-2.5">GST</th>
                <th className="px-4 py-2.5 text-right">Stock</th>
                <th className="px-4 py-2.5 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredItems.length === 0 ? (
                <tr>
                  <td
                    colSpan={canViewCosts ? 8 : 6}
                    className="px-4 py-14 text-center text-xs font-bold text-[var(--text-tertiary)]"
                  >
                    {items.length === 0 ? (
                      "No products yet. Add your first one, or import a spreadsheet."
                    ) : (
                      <>
                        No products match these filters.
                        {/* A dead end with no way out is how people conclude
                            the screen is broken. Offer the way back. */}
                        {filtersActive && (
                          <button
                            type="button"
                            onClick={() => {
                              setSearch(DEFAULT_FILTERS.search);
                              setCategoryFilter(DEFAULT_FILTERS.category);
                              setStockFilter(DEFAULT_FILTERS.stock);
                            }}
                            className="focus-ring ml-2 cursor-pointer font-bold text-[var(--primary-hover)] underline underline-offset-2"
                          >
                            Clear filters
                          </button>
                        )}
                      </>
                    )}
                  </td>
                </tr>
              ) : (
                filteredItems.map((item) => {
                  const margin = marginPercent(item);
                  const fill = stockFillPercent(item);
                  return (
                    <tr
                      key={item.id}
                      className="border-b border-[var(--border-soft)] transition-colors last:border-b-0 hover:bg-[var(--bg-base)]"
                    >
                      <td className="px-4 py-2">
                        <div className="flex items-center gap-2.5">
                          <span
                            className={`h-6 w-[3px] flex-none rounded-full ${
                              item.is_out_of_stock
                                ? "bg-[var(--error)]"
                                : item.is_low_stock
                                  ? "bg-[var(--warning)]"
                                  : "bg-transparent"
                            }`}
                            aria-hidden="true"
                          />
                          {/* The same picture the till shows, so what you set
                              here is what the cashier will be hitting. */}
                          <span className="grid h-8 w-8 flex-none place-items-center overflow-hidden rounded-[8px] border border-[var(--border-soft)] bg-[var(--bg-soft)]">
                            {item.has_image ? (
                              // eslint-disable-next-line @next/next/no-img-element
                              <img
                                src={`/api/inventory/${item.id}/image`}
                                alt=""
                                loading="lazy"
                                className="h-full w-full object-cover"
                              />
                            ) : (
                              <span className="text-[15px] font-extrabold text-[var(--primary-hover)] opacity-50">
                                {item.name.trim().charAt(0).toUpperCase()}
                              </span>
                            )}
                          </span>
                          <span className="min-w-0">
                            <span className="block text-[12.5px] font-extrabold text-[var(--text-primary)]">
                              {item.name}
                            </span>
                            <span className="mt-0.5 block font-mono text-[10.5px] font-medium text-[var(--text-tertiary)]">
                              {item.sku || "No SKU"}
                              {item.barcode ? ` · ${item.barcode}` : ""}
                              {item.unit ? ` · per ${item.unit}` : ""}
                            </span>
                          </span>
                        </div>
                      </td>

                      <td className="px-4 py-2">
                        <span className="inline-flex rounded-full border border-[var(--border-soft)] bg-[var(--bg-base)] px-2.5 py-1 text-[11px] font-bold text-[var(--text-secondary)]">
                          {item.category || "General"}
                        </span>
                      </td>

                      {canViewCosts && (
                        <td className="tnum px-4 py-2 text-right font-mono text-[12.5px] font-semibold">
                          {item.cost_price === null ? (
                            <span className="inline-flex rounded-full bg-[var(--warning)]/10 px-2.5 py-1 font-sans text-[11px] font-bold text-[var(--warning-strong)]">
                              Not set
                            </span>
                          ) : (
                            <span className="text-[var(--text-secondary)]">
                              {formatCurrency(item.cost_price)}
                            </span>
                          )}
                        </td>
                      )}

                      <td className="tnum px-4 py-2 text-right font-mono text-[12.5px] font-bold text-[var(--text-primary)]">
                        {formatCurrency(item.selling_price)}
                      </td>

                      {canViewCosts && (
                        <td
                          className={`tnum px-4 py-3 text-right font-mono text-[12.5px] font-semibold ${
                            margin === null
                              ? "text-[var(--text-tertiary)]"
                              : margin < 0
                                ? "text-[var(--error-strong)]"
                                : margin < 10
                                  ? "text-[var(--warning-strong)]"
                                  : "text-[var(--success-strong)]"
                          }`}
                        >
                          {margin === null ? "—" : `${margin.toFixed(1)}%`}
                        </td>
                      )}

                      <td className="px-4 py-2">
                        <span className="inline-flex rounded-full bg-[var(--primary)]/10 px-2.5 py-1 text-[11px] font-bold text-[var(--primary-hover)]">
                          {item.tax_rate === null ? "GST not set" : `GST ${item.tax_rate}%`}
                        </span>
                      </td>

                      <td className="px-4 py-2 text-right">
                        <span
                          className={`tnum block font-mono text-[12.5px] font-bold ${
                            !item.is_tracked
                              ? "text-[var(--text-tertiary)]"
                              : item.is_out_of_stock
                                ? "text-[var(--error-strong)]"
                                : item.is_low_stock
                                  ? "text-[var(--warning-strong)]"
                                  : "text-[var(--text-primary)]"
                          }`}
                        >
                          {/* Three states, not two. An item nobody ever
                              stocked has no count to report - printing "0" or
                              "-4" for it states a fact that was never
                              established. A tracked negative DOES show its
                              figure: hiding it as "Out" buries the one thing
                              that needs fixing. */}
                          {!item.is_tracked
                            ? "--"
                            : item.current_stock === 0
                              ? "Out"
                              : formatQuantity(item.current_stock)}
                        </span>
                        {/* No bar for an untracked item. An empty track is a
                            picture of an empty shelf, which is precisely the
                            claim we cannot make here. */}
                        {item.is_tracked && (
                          <span
                            className="mt-1.5 ml-auto block h-1 w-16 overflow-hidden rounded-full bg-[var(--border-soft)]"
                            title={
                              item.reorder_level === null
                                ? "No reorder level set"
                                : `Reorder level ${item.reorder_level}`
                            }
                          >
                            <span
                              className="block h-full rounded-full"
                              style={{
                                width: `${fill}%`,
                                background: item.is_out_of_stock
                                  ? "var(--error)"
                                  : item.is_low_stock
                                    ? "var(--warning)"
                                    : "var(--primary-bright)",
                              }}
                            />
                          </span>
                        )}
                      </td>

                      <td className="px-4 py-2">
                        <div className="flex items-center justify-end gap-1.5">
                          {canViewCosts && item.cost_price === null ? (
                            <button
                              onClick={() => openEditModal(item)}
                              className="focus-ring cursor-pointer rounded-lg border border-[var(--warning)]/40 bg-[var(--warning)]/10 px-2.5 py-1 text-[11px] font-bold text-[var(--warning-strong)] transition-colors hover:bg-[var(--warning)]/20"
                            >
                              Add cost
                            </button>
                          ) : (
                            <button
                              onClick={() => {
                                setAdjustItem(item);
                                setAdjustQty("10");
                                setAdjustType("inward");
                              }}
                              className="focus-ring cursor-pointer rounded-lg border border-[var(--border-soft)] bg-[var(--surface)] px-2.5 py-1 text-[11px] font-bold text-[var(--primary-hover)] transition-colors hover:border-[var(--primary)] hover:bg-[var(--primary)]/12 hover:text-[var(--primary-dark)] border border-[var(--primary)]/25"
                            >
                              {t("webAdjustStock")}
                            </button>
                          )}
                          <button
                            onClick={() => openEditModal(item)}
                            className="focus-ring cursor-pointer rounded-lg p-1.5 text-[var(--text-tertiary)] transition-colors hover:bg-[var(--bg-base)] hover:text-[var(--text-primary)]"
                            title={`Edit ${item.name}`}
                            aria-label={`Edit ${item.name}`}
                          >
                            <Edit2 className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
        )}

        <div className="flex flex-wrap items-center gap-3 border-t border-[var(--border-soft)] bg-[var(--bg-soft)] px-4 py-2.5 text-[11.5px] font-semibold text-[var(--text-tertiary)]">
          <span>
            Showing {filteredItems.length} of {items.length}
            {/* Said out loud, because filters only ever search what has been
                loaded. Without this the count reads as the whole catalogue and
                a search for something further down comes back empty. */}
            {nextCursor ? " loaded so far" : ""}
          </span>

          {nextCursor && (
            <button
              type="button"
              onClick={() => void loadMore()}
              disabled={loadingMore}
              className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3 py-1.5 text-[11.5px] font-extrabold text-[var(--primary-dark)] transition-colors duration-200 hover:bg-[var(--primary)]/20 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {loadingMore ? "Loading…" : "Load more products"}
            </button>
          )}
          {canViewCosts && avgMargin !== null && (
            <span className="ml-auto">
              Average margin{" "}
              <b className="tnum font-mono text-[var(--success-strong)]">
                {avgMargin.toFixed(1)}%
              </b>
            </span>
          )}
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
            className="w-full max-w-lg bg-[var(--surface)] border border-[var(--border)] rounded-[16px] shadow-2xl overflow-hidden flex flex-col max-h-[90vh]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-4 border-b border-[var(--border-soft)] flex items-center justify-between bg-[var(--bg-soft)] shadow-sm relative z-10">
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
              <FormSection title="What it is" hint="The name is the only part a customer sees on a receipt." />

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

              {/* A picture is what the cashier hits at the counter, so it is
                  worth asking for here rather than hiding it in a second step. */}
              <div>
                <label className="mb-1 block text-xs font-semibold text-[var(--text-secondary)]">
                  Product photo
                </label>

                <div className="flex items-center gap-3 rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-soft)] p-2.5">
                  <span className="grid h-12 w-12 flex-none place-items-center overflow-hidden rounded-[12px] border border-[var(--border-soft)] bg-[var(--surface)]">
                    {/* A picture just chosen is previewed from its own bytes;
                        one already stored comes from its address, because the
                        form no longer holds it. */}
                    {formImage || existingImageId ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={formImage || `/api/inventory/${existingImageId}/image`}
                        alt={formName ? `Photo of ${formName}` : "Product photo"}
                        className="h-full w-full object-cover"
                      />
                    ) : (
                      <span className="text-lg font-extrabold text-[var(--primary-hover)] opacity-50">
                        {(formName || "?").trim().charAt(0).toUpperCase()}
                      </span>
                    )}
                  </span>

                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <label className="focus-ring inline-flex cursor-pointer items-center gap-1.5 rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-1.5 text-[11.5px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--text-primary)]">
                        <ImagePlus className="h-3.5 w-3.5" />
                        {imageBusy ? "Working…" : formImage || existingImageId ? "Replace" : "Choose photo"}
                        <input
                          type="file"
                          accept="image/jpeg,image/png,image/webp"
                          className="sr-only"
                          disabled={imageBusy}
                          onChange={(e) => {
                            void handlePickImage(e.target.files?.[0]);
                            // Let the same file be picked again after a failure.
                            e.target.value = "";
                          }}
                        />
                      </label>

                      {(formImage || existingImageId) && (
                        <button
                          type="button"
                          onClick={() => {
                            setFormImage("");
                            setImageDirty(true);
                            setExistingImageId(null);
                            setImageError("");
                          }}
                          className="focus-ring cursor-pointer rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-1.5 text-[11.5px] font-bold text-[var(--text-secondary)] transition-colors hover:text-[var(--error-strong)]"
                        >
                          Remove
                        </button>
                      )}
                    </div>

                    <p className="mt-1.5 text-[11px] font-semibold text-[var(--text-tertiary)]">
                      {imageError ? (
                        <span className="text-[var(--error-strong)]">{imageError}</span>
                      ) : formImage ? (
                        `Stored at ${formatBytes(dataUriBytes(formImage))} — shrunk to fit a till tile.`
                      ) : (
                        "Optional. Shrunk in the browser before saving, so the counter loads fast."
                      )}
                    </p>
                  </div>
                </div>
              </div>

              <FormSection title="Price and tax" hint="Cost is never shown to a customer. Selling price is what they pay." />

              <div>
                <label className="block text-xs font-semibold text-[var(--text-secondary)] mb-1">
                  HSN / SAC Code
                </label>
                <input
                  type="text"
                  value={formHsnCode}
                  onChange={(e) => setFormHsnCode(e.target.value)}
                  placeholder="e.g. 1512"
                  maxLength={16}
                  className="w-full px-3 py-2 bg-bg-soft border border-[var(--border-soft)] rounded-xl text-xs text-text-primary focus:outline-none"
                />
                <p className="mt-1 text-[11px] font-semibold text-[var(--text-tertiary)]">
                  Required on a GST invoice. Four digits is enough below ₹5
                  crore turnover.
                </p>
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

              {/* Its own row rather than tucked under Selling Price. Nested
                  there it made the two-column row lopsided - a short field on
                  the left beside a tall stack on the right - and the question
                  it asks is about the price, not about that one box. */}
                  {/* Immediately under the price, because the person typing the
                  price is the person who has to answer this, at that
                  moment. A distant setting in another screen would not get
                  used. */}
              {parseFloat(formTaxRate) > 0 && (
                <div className="mt-2">
                  <div className="flex gap-1 p-0.5 bg-bg-soft border border-[var(--border-soft)] rounded-xl">
                    {[
                      { value: true, label: "Includes GST" },
                      { value: false, label: "GST extra" },
                    ].map((option) => (
                      <button
                        key={String(option.value)}
                        type="button"
                        onClick={() => setFormPriceIncludesTax(option.value)}
                        className={`flex-1 px-2 py-1.5 rounded-lg text-[11px] font-bold transition-colors ${
                          formPriceIncludesTax === option.value
                            ? "bg-[var(--primary)]/12 text-[var(--primary-dark)] border border-[var(--primary)]/25 hover:bg-[var(--primary)]/20"
                            : "text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                        }`}
                      >
                        {option.label}
                      </button>
                    ))}
                  </div>
                  {/* The whole feature, really. A shopkeeper who has never
                      met the phrase "inclusive of tax" can still see which
                      answer matches the number they meant. */}
                  <p className="mt-1.5 text-[11px] font-semibold text-[var(--text-tertiary)]">
                    {(() => {
                      const price = parseFloat(formSellingPrice) || 0;
                      const rate = (parseFloat(formTaxRate) || 0) / 100;
                      if (price <= 0) return "Customer pays the price above.";
                      const taxable = formPriceIncludesTax
                        ? price / (1 + rate)
                        : price;
                      const tax = formPriceIncludesTax
                        ? price - taxable
                        : price * rate;
                      return `Customer pays ₹${(taxable + tax).toFixed(2)} = ₹${taxable.toFixed(2)} + ₹${tax.toFixed(2)} GST`;
                    })()}
                  </p>
                </div>
              )}

              <FormSection title="Stock" hint="What is on the shelf now, and when to reorder." />

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
                  disabled={isSubmitting}
                  className="px-5 py-2 text-xs font-semibold text-[var(--primary-dark)] bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 disabled:opacity-50 rounded-xl border border-[var(--primary)]/25"
                >
                  {isSubmitting ? "Saving…" : "Save Product"}
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
                  Current Stock:{" "}
                  <strong>{formatQuantity(adjustItem.current_stock)} units</strong>
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
                  disabled={isSubmitting}
                  className="px-5 py-2 text-xs font-semibold text-[var(--primary-dark)] bg-[var(--primary)]/12/12 hover:bg-[var(--primary)]/12/20 disabled:opacity-50 rounded-xl shadow-md border border-[var(--primary)]/25"
                >
                  {isSubmitting ? "Saving…" : t("webConfirmAdjustment")}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
