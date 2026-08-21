"use client";

import React, { useState, useEffect, useMemo, useRef } from "react";
import {
  Search,
  Barcode,
  Plus,
  Minus,
  Trash2,
  ShoppingCart,
  User,
  X,
  CreditCard,
} from "lucide-react";
import { formatCurrency } from "@/lib/utils";
import { PosCheckoutModal } from "@/components/pos-checkout-modal";
import { CameraScanButton } from "@/components/camera-scanner";
import { ThermalReceiptModal } from "@/components/thermal-receipt-modal";
import type {
  CartItem,
  Customer,
  SplitPaymentTender,
} from "@/lib/types";
import type { ProductItem } from "@/components/inventory-manager";
import { useT } from "@/lib/i18n";
import { computeCartTotals } from "@/lib/cart-totals";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
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
  unit?: string;
  price_includes_tax?: boolean;
};

type PosTerminalProps = {
  shopName?: string;
  shopAddress?: string;
  shopGstin?: string;
  shopPhone?: string;
  cashierName?: string;
  initialInventory: ApiInventoryRow[];
  initialCustomers: Customer[];
  shopId: string;
};

export function PosTerminal({
  shopName = "Business Hub Superstore",
  shopAddress = "Shop 12-14, Commercial Complex, Sector 18",
  shopGstin = "27AABCU9603R1ZM",
  shopPhone = "+91 98765 43210",
  cashierName = "Rashi (Cashier #1)",
  initialInventory,
  initialCustomers,
}: PosTerminalProps) {
  const t = useT();
  const mappedInitialProducts = React.useMemo(() => {
    return (initialInventory ?? []).map((item: ApiInventoryRow) => ({
      id: item.id,
      name: item.name,
      sku: item.sku ?? "",
      barcode: item.barcode ?? "",
      category: item.category || "General",
      cost_price: parseFloat(item.cost_price || "0"),
      selling_price: parseFloat(item.sell_price || "0"),
      current_stock: item.stock_on_hand || 0,
      reorder_level: 0,
      tax_rate: parseFloat(item.gst_rate || "0"),
      is_low_stock: false,
      status: item.status ?? "active",
      unit: item.unit ?? "",
      price_includes_tax: item.price_includes_tax ?? true,
    }));
  }, [initialInventory]);

  const [products, setProducts] = useState<ProductItem[]>(mappedInitialProducts);
  const [customers, setCustomers] = useState<Customer[]>(initialCustomers ?? []);
  const [_isLoading, _setIsLoading] = useState(false);
  const [_error, setError] = useState<string | null>(null);
  
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedCategory, setSelectedCategory] = useState("All");
  const [cart, setCart] = useState<CartItem[]>([]);
  // Whether this shop sells loose goods by weight. Off for most shops, and the
  // whole product for a kirana: without it the quantity is integer-only, so
  // 1.25 kg of dal simply cannot be rung up.
  const [weightSelling, setWeightSelling] = useState(false);
  // Wholesale sells B2B, where the buyer needs a GSTIN on the invoice to claim
  // input credit. Retail mostly sells to people who have none, so this is off
  // unless the shop asked for it.
  const [requireBuyerGstin, setRequireBuyerGstin] = useState(false);
  // Stops a second submit while the first is in flight. There was no guard at
  // all, and the only disabled= on the pay button was "is the cart empty" — so
  // an impatient second press on a slow connection rang the bill twice.
  const [isSubmitting, setIsSubmitting] = useState(false);
  //: One id per CART, not per attempt. Generated when the cart becomes
  //: non-empty and held until the sale completes, so every retry of the same
  //: bill carries the same id and the server can recognise it as one sale.
  //: Regenerating per attempt would make the whole mechanism useless.
  const commandIdRef = useRef<string>("");
  const [selectedCustomer, setSelectedCustomer] = useState<Customer | null>(null);
  const [customerSearch, setCustomerSearch] = useState("");
  const [showCustomerDropdown, setShowCustomerDropdown] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const res = await fetch("/api/settings");
        if (!res.ok) return;
        const data = await res.json();
        if (cancelled) return;
        setWeightSelling(data?.features?.weight_selling === true);
        setRequireBuyerGstin(data?.features?.gstin_on_every_bill === true);
      } catch {
        // Left off on a failure, deliberately. The till must open whatever the
        // settings endpoint is doing, and an integer quantity is the behaviour
        // every shop had until now — wrong for a grocer, but not broken.
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    async function _loadData() {
      try {
        // Load inventory
        const invRes = await fetch("/api/inventory");
        if (!invRes.ok) throw new Error("Failed to load inventory");
        const invData = await invRes.json();
        
        // Map backend InventoryItem to ProductItem
        const mappedProducts: ProductItem[] = invData.map((item: ApiInventoryRow) => ({
          id: item.id,
          name: item.name,
          sku: item.sku ?? "",
          barcode: item.barcode ?? "",
          category: item.category || "General",
          cost_price: parseFloat(item.cost_price || "0"),
          selling_price: parseFloat(item.sell_price || "0"),
          current_stock: item.stock_on_hand || 0,
          reorder_level: 0,
          tax_rate: parseFloat(item.gst_rate || "0"),
          is_low_stock: false,
          status: item.status ?? "active",
          unit: item.unit ?? "",
          price_includes_tax: item.price_includes_tax ?? true,
        }));
        setProducts(mappedProducts);

        // Load customers
        const custRes = await fetch("/api/customers");
        if (!custRes.ok) throw new Error("Failed to load customers");
        const custData = await custRes.json();
        setCustomers(custData);
      } catch (err) {
        setError(errorMessage(err, "Failed to load POS data"));
      }
    }
    // We already loaded initial data server-side, but keep this to pull fresh updates if needed
  }, []);

  // Modals state
  const [isCheckoutOpen, setIsCheckoutOpen] = useState(false);
  const [isReceiptOpen, setIsReceiptOpen] = useState(false);
  const [lastSaleReceipt, setLastSaleReceipt] = useState<{
    receiptNumber: string;
    items: CartItem[];
    subtotal: number;
    taxAmount: number;
    discountAmount: number;
    totalAmount: number;
    payments: SplitPaymentTender;
    changeDue: number;
    customerName?: string;
    customerPhone?: string;
  } | null>(null);

  const searchInputRef = useRef<HTMLInputElement>(null);

  // Keyboard Shortcuts: '/' to focus search, 'F2' to checkout
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      const isInput =
        target.tagName === "INPUT" || target.tagName === "TEXTAREA";

      if (e.key === "/" && !isInput) {
        e.preventDefault();
        searchInputRef.current?.focus();
      } else if (e.key === "F2") {
        e.preventDefault();
        if (cart.length > 0) {
          setIsCheckoutOpen(true);
        }
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [cart]);

  // Categories list
  const categories = useMemo(() => {
    const list = Array.from(
      new Set(products.map((p) => p.category).filter((c): c is string => Boolean(c)))
    );
    return ["All", ...list];
  }, [products]);

  // Filtered Products
  const filteredProducts = useMemo(() => {
    let result = products;
    if (selectedCategory !== "All") {
      result = result.filter((p) => p.category === selectedCategory);
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      result = result.filter(
        (p) =>
          p.name.toLowerCase().includes(q) ||
          p.sku.toLowerCase().includes(q) ||
          (p.barcode && p.barcode.includes(q))
      );
    }
    return result;
  }, [products, selectedCategory, searchQuery]);

  // Cart operations
  /**
   * A code read from the camera.
   *
   * An exact barcode or SKU match goes straight into the cart — that is the
   * whole point of scanning, and making the cashier tap again would be slower
   * than typing. Anything unrecognised is dropped into the search box instead
   * of failing silently, so a mis-read is visible and correctable.
   */
  const handleScannedCode = (code: string) => {
    const scanned = code.trim().toLowerCase();
    const match = products.find(
      (p) =>
        (p.barcode ?? "").trim().toLowerCase() === scanned ||
        p.sku.trim().toLowerCase() === scanned,
    );
    if (match) {
      addToCart(match);
      return;
    }
    setSearchQuery(code.trim());
  };

  const addToCart = (product: ProductItem) => {
    setCart((prev) => {
      const existing = prev.find((item) => item.product_id === product.id);
      if (existing) {
        return prev.map((item) =>
          item.product_id === product.id
            ? {
                ...item,
                quantity: item.quantity + 1,
                total_price: (item.quantity + 1) * item.unit_price - item.discount_amount,
              }
            : item
        );
      }
      const newItem: CartItem = {
        id: `cart-${Date.now()}-${Math.random()}`,
        product_id: product.id,
        name: product.name,
        sku: product.sku,
        barcode: product.barcode || "",
        unit_price: product.selling_price,
        cost_price: product.cost_price,
        tax_rate: product.tax_rate ?? 0,
        quantity: 1,
        discount_amount: 0,
        total_price: product.selling_price,
        available_stock: product.current_stock,
        unit: product.unit || "",
        price_includes_tax: product.price_includes_tax ?? true,
      };
      return [...prev, newItem];
    });
  };

  const updateQuantity = (cartItemId: string, newQty: number) => {
    if (newQty <= 0) {
      removeFromCart(cartItemId);
      return;
    }
    // The backend stores quantity to three decimals. Rounding here keeps the
    // line total the customer is shown identical to the one that gets stored,
    // rather than off by a fraction of a paisa that nobody can explain.
    newQty = Math.round(newQty * 1000) / 1000;
    setCart((prev) =>
      prev.map((item) =>
        item.id === cartItemId
          ? {
              ...item,
              quantity: newQty,
              total_price: newQty * item.unit_price - item.discount_amount,
            }
          : item
      )
    );
  };

  const removeFromCart = (cartItemId: string) => {
    setCart((prev) => prev.filter((item) => item.id !== cartItemId));
  };

  const clearCart = () => {
    setCart([]);
    setSelectedCustomer(null);
  };

  const handleSearchKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter" && filteredProducts.length === 1) {
      e.preventDefault();
      addToCart(filteredProducts[0]);
      setSearchQuery("");
    }
  };

  // Financial Calculations
  // One source of arithmetic, shared with the tests that pin it to the
  // server's. Inline in this component it could not be tested, and it was
  // wrong: it added GST on top of an MRP that already contained it.
  const totals = useMemo(() => computeCartTotals(cart), [cart]);
  const cartSubtotal = totals.subtotal;
  const cartDiscounts = totals.discounts;
  const cartTaxBreakdown = totals;
  const grandTotal = totals.grandTotal;

  const handleCompleteSale = async (
    payments: SplitPaymentTender,
    changeDue: number,
    buyerGstin?: string,
  ) => {
    if (isSubmitting) return;
    setIsSubmitting(true);
    if (!commandIdRef.current) {
      commandIdRef.current = crypto.randomUUID();
    }
    try {
      const backendPayments = [];
      if (payments.cash > 0) {
        backendPayments.push({ payment_method: "CASH", amount: payments.cash.toString() });
      }
      if (payments.upi > 0) {
        backendPayments.push({ payment_method: "UPI", amount: payments.upi.toString(), reference_code: payments.upi_ref || "" });
      }
      if (payments.card > 0) {
        backendPayments.push({ payment_method: "CARD", amount: payments.card.toString(), reference_code: payments.card_ref || "" });
      }
      if (payments.khata_due > 0) {
        backendPayments.push({ payment_method: "CREDIT", amount: payments.khata_due.toString() });
      }

      if (backendPayments.length === 0) {
        backendPayments.push({ payment_method: "CASH", amount: grandTotal.toString() });
      }

      const salePayload = {
        customer_id: selectedCustomer?.id || null,
        subtotal_amount: cartSubtotal.toFixed(2),
        discount_amount: cartDiscounts.toFixed(2),
        total_amount: grandTotal.toFixed(2),
        items: cart.map(item => ({
          inventory_item_id: item.product_id,
          quantity: item.quantity,
          unit_price: item.unit_price.toFixed(2),
        })),
        payments: backendPayments,
        // Omitted rather than sent empty when the shop does not collect it —
        // the column is nullable and a blank string is not the same as "this
        // buyer has no GSTIN".
        ...(buyerGstin ? { buyer_gstin: buyerGstin } : {}),
        // Makes this bill identifiable across retries. The server keeps a
        // receipt per (shop, command_id) and returns the original sale rather
        // than creating a second one.
        command_id: commandIdRef.current,
      };

      const res = await fetch("/api/sales", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(salePayload),
      });

      if (!res.ok) {
        const errText = await res.text();
        // Safe to say "try again" now: the bill carries a command_id, so a
        // retry that reaches a server which already recorded it returns the
        // original sale instead of ringing a second one.
        alert(
          `Could not save the sale: ${errText}

Press Pay again to retry — ` +
          `the bill will not be charged twice.`
        );
        return;
      }

      const savedSale = await res.json();
      const receiptNum = savedSale.receipt_number || `INV-${Date.now().toString().slice(-6)}`;

      setLastSaleReceipt({
        receiptNumber: receiptNum,
        items: [...cart],
        subtotal: cartSubtotal,
        taxAmount: cartTaxBreakdown.totalTax,
        discountAmount: cartDiscounts,
        totalAmount: grandTotal,
        payments,
        changeDue,
        customerName: selectedCustomer?.name,
        customerPhone: selectedCustomer?.phone,
      });

      setIsCheckoutOpen(false);
      setIsReceiptOpen(true);
      setCart([]);
      setSelectedCustomer(null);
      // This bill is done; the next cart gets a fresh id. Deliberately here
      // and not in a finally block — on failure the id must SURVIVE so the
      // retry is recognised as the same sale.
      commandIdRef.current = "";
      
      // Reload inventory from backend to update stock indicators
      const invRes = await fetch("/api/inventory");
      if (invRes.ok) {
        const invData = await invRes.json();
        const mappedProducts: ProductItem[] = invData.map((item: ApiInventoryRow) => ({
          id: item.id,
          name: item.name,
          sku: item.sku ?? "",
          barcode: item.barcode ?? "",
          category: item.category || "General",
          cost_price: parseFloat(item.cost_price || "0"),
          selling_price: parseFloat(item.sell_price || "0"),
          current_stock: item.stock_on_hand || 0,
          reorder_level: 0,
          tax_rate: parseFloat(item.gst_rate || "0"),
          is_low_stock: false,
          status: item.status ?? "active",
          unit: item.unit ?? "",
          price_includes_tax: item.price_includes_tax ?? true,
        }));
        setProducts(mappedProducts);
      }
    } catch (err) {
      alert(`Error submitting sale: ${errorMessage(err, "Unknown error")}`);
    } finally {
      // Always. Without this the button stays disabled after the first sale
      // and the till is dead for the rest of the shift — a far worse failure
      // than the double-submit being prevented. The early return on a failed
      // response makes it easy to miss, which is exactly why it is in finally
      // rather than at the end of the happy path.
      setIsSubmitting(false);
    }
  };

  return (
    <div className="flex flex-col lg:flex-row gap-6 min-h-[calc(100vh-14rem)]">
      {/* ========================================================= */}
      {/* LEFT COLUMN: Product Catalog & Search                      */}
      {/* ========================================================= */}
      <div className="flex-1 flex flex-col min-w-0 bg-[var(--surface)] border border-[var(--border-soft)] rounded-[28px] overflow-hidden shadow-sm">
        {/* Search Bar & Barcode Scanner */}
        <div className="p-4 border-b border-[var(--bg-soft)] bg-[var(--bg-base)] flex items-center gap-3">
          <div className="relative flex-1">
            <Search className="w-4 h-4 text-[var(--text-tertiary)] absolute left-3.5 top-1/2 -translate-y-1/2" />
            <input
              ref={searchInputRef}
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onKeyDown={handleSearchKeyDown}
              placeholder="Scan barcode or search product / SKU... (Press / to focus)"
              className="w-full pl-10 pr-10 py-3 bg-[var(--surface)] border border-[var(--border-soft)] focus:border-[var(--primary)] rounded-2xl text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none shadow-sm transition-all"
            />
            {searchQuery && (
              <button
                onClick={() => setSearchQuery("")}
                className="absolute right-3.5 top-1/2 -translate-y-1/2 text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
              >
                <X className="w-4 h-4" />
              </button>
            )}
          </div>
          <CameraScanButton onDetected={handleScannedCode} />
          <div className="hidden sm:flex items-center gap-2 px-4 py-3 bg-[var(--surface)] rounded-2xl border border-[var(--border-soft)] text-xs font-bold text-[var(--primary-hover)] shadow-sm">
            <Barcode className="w-4 h-4" />
            <span>Scanner Ready</span>
          </div>
        </div>

        {/* Category Pills Bar */}
        <div className="flex items-center gap-2 p-3 overflow-x-auto border-b border-[var(--bg-soft)] bg-[var(--surface)] no-scrollbar">
          {categories.map((cat) => (
            <button
              key={cat}
              onClick={() => setSelectedCategory(cat)}
              className={`px-4 py-2 rounded-xl text-xs font-bold shrink-0 transition-all ${
                selectedCategory === cat
                  ? "bg-[var(--primary)] text-white shadow-md shadow-[var(--primary)]/25"
                  : "bg-[var(--bg-base)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] border border-[var(--border-soft)]"
              }`}
            >
              {cat}
            </button>
          ))}
        </div>

        {/* Product Grid */}
        <div className="flex-1 overflow-y-auto p-4 grid grid-cols-2 sm:grid-cols-3 xl:grid-cols-4 gap-3.5">
          {filteredProducts.length === 0 ? (
            <div className="col-span-full py-16 text-center text-[var(--text-tertiary)] text-xs font-bold">
              No products found matching &quot;{searchQuery}&quot;.
            </div>
          ) : (
            filteredProducts.map((prod) => (
              <button
                key={prod.id}
                onClick={() => addToCart(prod)}
                className="group relative flex flex-col justify-between p-4 rounded-2xl bg-[var(--bg-base)] hover:bg-[var(--surface)] border border-[var(--border-soft)] hover:border-[var(--primary)] hover:shadow-md text-left transition-all active:scale-98"
              >
                <div>
                  <div className="flex items-start justify-between gap-1 mb-1.5">
                    <span className="text-[10px] font-bold text-[var(--text-tertiary)] truncate">
                      {prod.sku}
                    </span>
                    {(prod.tax_rate ?? 0) > 0 ? (
                      <span className="text-[9px] font-extrabold px-2 py-0.5 rounded-md bg-[var(--primary)]/10 text-[var(--primary-hover)]">
                        GST {prod.tax_rate ?? 0}%
                      </span>
                    ) : (
                      <span className="text-[9px] font-extrabold px-2 py-0.5 rounded-md bg-[var(--success)]/10 text-[var(--success-strong)]">
                        0% Tax
                      </span>
                    )}
                  </div>
                  <h4 className="text-xs font-extrabold text-[var(--text-primary)] line-clamp-2 leading-snug group-hover:text-[var(--primary-hover)]">
                    {prod.name}
                  </h4>
                </div>

                <div className="mt-4 pt-2.5 border-t border-[var(--border-soft)] flex items-center justify-between">
                  <span className="text-sm font-[900] text-[var(--text-primary)]">
                    {formatCurrency(prod.selling_price)}
                  </span>
                  <span
                    className={`text-[10px] font-bold ${
                      prod.is_low_stock
                        ? "text-[var(--error-strong)] font-extrabold"
                        : "text-[var(--text-secondary)]"
                    }`}
                  >
                    Qty: {prod.current_stock}
                  </span>
                </div>
              </button>
            ))
          )}
        </div>
      </div>

      {/* ========================================================= */}
      {/* RIGHT COLUMN: Interactive Cart & Tender Total              */}
      {/* ========================================================= */}
      <div className="w-full lg:w-[420px] flex flex-col bg-[var(--surface)] border border-[var(--border-soft)] rounded-[28px] overflow-hidden shadow-sm shrink-0">
        {/* Cart Header */}
        <div className="p-4 border-b border-[var(--bg-soft)] bg-[var(--bg-base)] flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-[var(--primary)]/10 flex items-center justify-center text-[var(--primary-hover)]">
              <ShoppingCart className="w-4 h-4" />
            </div>
            <span className="font-extrabold text-sm text-[var(--text-primary)]">
              {t("webCurrentCart")}
            </span>
            <span className="px-2.5 py-0.5 text-xs font-extrabold bg-[var(--primary)] text-white rounded-full">
              {/* Rounded: adding 0.1 + 0.2 in binary floating point gives
                  0.30000000000000004, and a badge on a till reading that
                  destroys confidence in every other number on the screen. */}
              {Math.round(cart.reduce((s, i) => s + i.quantity, 0) * 1000) / 1000}
            </span>
          </div>

          {cart.length > 0 && (
            <button
              onClick={clearCart}
              className="text-xs text-[var(--error-strong)] hover:text-[var(--error-strong)] hover:underline font-bold"
            >
              {t("webClearCart")}
            </button>
          )}
        </div>

        {/* Customer Selector Bar */}
        <div className="p-3 border-b border-[var(--bg-soft)] bg-[var(--surface)] relative">
          {selectedCustomer ? (
            <div className="flex items-center justify-between p-2.5 rounded-2xl bg-[var(--primary)]/10 border border-[var(--primary)]/30">
              <div className="flex items-center gap-2.5 min-w-0">
                <div className="w-8 h-8 rounded-xl bg-[var(--primary)] text-white flex items-center justify-center text-xs font-black shrink-0">
                  {selectedCustomer.name.charAt(0)}
                </div>
                <div className="truncate">
                  <div className="text-xs font-extrabold text-[var(--text-primary)] truncate">
                    {selectedCustomer.name}
                  </div>
                  <div className="text-[10px] font-bold text-[var(--primary-hover)] truncate">
                    Khata Due: {formatCurrency(selectedCustomer.balance_amount ?? 0)}
                  </div>
                </div>
              </div>
              <button
                onClick={() => setSelectedCustomer(null)}
                className="p-1 text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          ) : (
            <div className="relative">
              <div className="flex items-center gap-2 px-3 py-2 bg-[var(--bg-base)] border border-[var(--border-soft)] rounded-xl">
                <User className="w-4 h-4 text-[var(--text-tertiary)]" />
                <input
                  type="text"
                  value={customerSearch}
                  onFocus={() => setShowCustomerDropdown(true)}
                  onChange={(e) => {
                    setCustomerSearch(e.target.value);
                    setShowCustomerDropdown(true);
                  }}
                  placeholder="Attach Khata / Customer Account..."
                  className="flex-1 bg-transparent text-xs font-semibold text-[var(--text-primary)] placeholder-[var(--text-tertiary)] outline-none"
                />
              </div>

              {/* Customer Dropdown */}
              {showCustomerDropdown && (
                <div className="absolute left-0 right-0 top-full mt-2 bg-[var(--surface)] border border-[var(--border-soft)] rounded-2xl shadow-xl z-20 max-h-52 overflow-y-auto p-1.5">
                  {customers
                    .filter(
                      (c) =>
                        c.name.toLowerCase().includes(customerSearch.toLowerCase()) ||
                        c.phone?.includes(customerSearch)
                    )
                    .map((c) => (
                      <button
                        key={c.id}
                        onClick={() => {
                          setSelectedCustomer(c);
                          setShowCustomerDropdown(false);
                          setCustomerSearch("");
                        }}
                        className="w-full flex items-center justify-between p-2.5 hover:bg-[var(--bg-base)] rounded-xl text-left text-xs transition-colors"
                      >
                        <div>
                          <div className="font-extrabold text-[var(--text-primary)]">{c.name}</div>
                          <div className="text-[10px] text-[var(--text-secondary)]">{c.phone}</div>
                        </div>
                        <div className="text-right">
                          <div className="text-[10px] font-bold text-[var(--warning-strong)]">
                            Due: {formatCurrency(c.balance_amount ?? 0)}
                          </div>
                        </div>
                      </button>
                    ))}
                  <button
                    onClick={() => setShowCustomerDropdown(false)}
                    className="w-full text-center py-2 text-[10px] font-bold text-[var(--text-tertiary)] hover:text-[var(--text-primary)] border-t border-[var(--bg-soft)]"
                  >
                    Close Dropdown
                  </button>
                </div>
              )}
            </div>
          )}
        </div>

        {/* Cart Items List */}
        <div className="flex-1 overflow-y-auto p-4 space-y-3 divide-y divide-[var(--bg-soft)]">
          {cart.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center p-8 text-[var(--text-tertiary)]">
              <ShoppingCart className="w-12 h-12 stroke-1 mb-2 text-[var(--border)]" />
              <p className="text-xs font-bold">Cart is currently empty</p>
              <p className="text-[11px] text-[var(--text-tertiary)] mt-1">
                Scan barcode or click items to add to cart
              </p>
            </div>
          ) : (
            cart.map((item) => (
              <div key={item.id} className="pt-3 first:pt-0 flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <h5 className="text-xs font-extrabold text-[var(--text-primary)] truncate">{item.name}</h5>
                  <div className="flex items-center gap-2 text-[10px] font-bold text-[var(--text-secondary)] mt-0.5">
                    <span>{formatCurrency(item.unit_price)}</span>
                    <span>•</span>
                    <span>GST {item.tax_rate}%</span>
                  </div>

                  {/* Quantity Stepper Controls */}
                  <div className="flex items-center gap-2 mt-2">
                    <div className="flex items-center border border-[var(--border-soft)] rounded-xl bg-[var(--bg-base)]">
                      <button
                        onClick={() => updateQuantity(item.id, item.quantity - 1)}
                        className="p-1.5 text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                      >
                        <Minus className="w-3.5 h-3.5" />
                      </button>
                      {weightSelling ? (
                        // Typed, not stepped. Reaching 1.25 kg by pressing +
                        // is not a slower way to do this; it is impossible.
                        <input
                          type="number"
                          inputMode="decimal"
                          step="0.001"
                          min="0"
                          aria-label={`Quantity${item.unit ? ` in ${item.unit}` : ""} for ${item.name}`}
                          value={item.quantity}
                          onChange={(e) => {
                            const next = parseFloat(e.target.value);
                            // An empty or half-typed box (".", "-") parses to
                            // NaN. Removing the line as someone clears it to
                            // retype would be maddening, so it is ignored.
                            if (Number.isFinite(next) && next > 0) {
                              updateQuantity(item.id, next);
                            }
                          }}
                          className="w-16 px-1 py-0.5 text-center text-xs font-black text-[var(--text-primary)] bg-transparent border-0 focus:outline-none focus:ring-1 focus:ring-[var(--primary)] rounded"
                        />
                      ) : (
                        <span className="px-2.5 text-xs font-black text-[var(--text-primary)]">
                          {item.quantity}
                        </span>
                      )}
                      {weightSelling && item.unit && (
                        <span className="pr-1.5 text-[10px] font-bold text-[var(--text-tertiary)]">
                          {item.unit}
                        </span>
                      )}
                      <button
                        onClick={() => updateQuantity(item.id, item.quantity + 1)}
                        className="p-1.5 text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                      >
                        <Plus className="w-3.5 h-3.5" />
                      </button>
                    </div>

                    <button
                      onClick={() => removeFromCart(item.id)}
                      className="p-1.5 text-[var(--error-strong)] hover:text-[var(--error-strong)] hover:bg-[var(--error)]/10 rounded-lg transition-colors"
                      title="Remove item"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                <div className="text-right">
                  <div className="text-sm font-[900] text-[var(--text-primary)]">
                    {formatCurrency(item.total_price)}
                  </div>
                </div>
              </div>
            ))
          )}
        </div>

        {/* Financial Summary & Checkout Button */}
        <div className="p-5 border-t border-[var(--bg-soft)] bg-[var(--bg-base)] space-y-3">
          <div className="space-y-1.5 text-xs font-semibold text-[var(--text-secondary)]">
            <div className="flex justify-between">
              <span>Subtotal:</span>
              <span className="text-[var(--text-primary)] font-bold">
                {formatCurrency(cartSubtotal)}
              </span>
            </div>
            {cartDiscounts > 0 && (
              <div className="flex justify-between text-[var(--success-strong)]">
                <span>Total Discount:</span>
                <span className="font-bold">-{formatCurrency(cartDiscounts)}</span>
              </div>
            )}
            <div className="flex justify-between text-[11px]">
              <span>Tax (GST CGST+SGST):</span>
              <span className="text-[var(--text-secondary)]">
                {formatCurrency(cartTaxBreakdown.totalTax)}
              </span>
            </div>
          </div>

          <div className="pt-3 border-t border-[var(--border-soft)] flex items-baseline justify-between">
            <div>
              <div className="text-[10px] uppercase font-black tracking-wider text-[var(--text-tertiary)]">
                {t("webGrandTotal")}
              </div>
              <div className="text-2xl font-[900] text-[var(--primary-hover)] tracking-tight">
                {formatCurrency(grandTotal)}
              </div>
            </div>

            <button
              disabled={cart.length === 0 || isSubmitting}
              onClick={() => setIsCheckoutOpen(true)}
              className="flex items-center gap-2 px-6 py-3.5 bg-gradient-to-r from-[var(--primary-light)] to-[var(--primary-hover)] hover:from-[var(--primary)] hover:to-[var(--primary-dark)] disabled:opacity-40 text-text-primary font-extrabold text-xs rounded-2xl shadow-[0_8px_20px_rgba(14,165,233,0.35)] transition-all cursor-pointer"
            >
              <CreditCard className="w-4 h-4" />
              <span>CHARGE (F2)</span>
            </button>
          </div>
        </div>
      </div>

      {/* ========================================================= */}
      {/* MODALS: Split Tender Payment & Thermal Receipt            */}
      {/* ========================================================= */}
      <PosCheckoutModal
        isOpen={isCheckoutOpen}
        onClose={() => setIsCheckoutOpen(false)}
        totalAmount={grandTotal}
        selectedCustomer={selectedCustomer}
        shopName={shopName}
        requireBuyerGstin={requireBuyerGstin}
        onCompleteSale={handleCompleteSale}
      />

      {lastSaleReceipt && (
        <ThermalReceiptModal
          isOpen={isReceiptOpen}
          onClose={() => setIsReceiptOpen(false)}
          shopName={shopName}
          shopAddress={shopAddress}
          shopGstin={shopGstin}
          shopPhone={shopPhone}
          receiptNumber={lastSaleReceipt.receiptNumber}
          cashierName={cashierName}
          customerName={lastSaleReceipt.customerName}
          customerPhone={lastSaleReceipt.customerPhone}
          items={lastSaleReceipt.items}
          subtotal={lastSaleReceipt.subtotal}
          taxAmount={lastSaleReceipt.taxAmount}
          discountAmount={lastSaleReceipt.discountAmount}
          totalAmount={lastSaleReceipt.totalAmount}
          payments={lastSaleReceipt.payments}
          changeDue={lastSaleReceipt.changeDue}
        />
      )}
    </div>
  );
}
