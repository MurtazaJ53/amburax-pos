import { getServerT } from "@/lib/i18n/server";
import { formatCurrency } from "@/lib/formatters";
import type { InventoryItem } from "@/lib/types";

type InventoryTableProps = {
  items: InventoryItem[];
  currencyCode?: string;
  showSupplierColumn?: boolean;
  showPurchaseColumn?: boolean;
};

export async function InventoryTable({
  items,
  currencyCode = "INR",
  showSupplierColumn = false,
  showPurchaseColumn = false,
}: InventoryTableProps) {
  const t = await getServerT();
  const columnCount = 6 + (showSupplierColumn ? 1 : 0) + (showPurchaseColumn ? 1 : 0);
  return (
    <div className="panel-soft overflow-hidden rounded-[28px]">
      <div className="overflow-x-auto">
        <table className="min-w-full border-collapse">
          <thead>
            <tr className="border-b border-[var(--border-soft)] text-left text-xs uppercase tracking-[0.24em] text-[var(--text-muted)]">
              <th className="px-5 py-4 font-medium">Item</th>
              <th className="px-5 py-4 font-medium">{t("webCategory", "Category")}</th>
              <th className="px-5 py-4 font-medium">SKU</th>
              <th className="px-5 py-4 font-medium">Stock</th>
              <th className="px-5 py-4 font-medium">Sell price</th>
              {showSupplierColumn ? (
                <th className="px-5 py-4 font-medium">Supplier</th>
              ) : null}
              {showPurchaseColumn ? (
                <th className="px-5 py-4 font-medium">Last buy</th>
              ) : null}
              <th className="px-5 py-4 font-medium">Status</th>
            </tr>
          </thead>
          <tbody>
            {items.length ? (
              items.map((item) => {
                const tone =
                  item.stock_on_hand <= 0
                    ? "text-[var(--warning)]"
                    : item.stock_on_hand <= 5
                      ? "text-[var(--accent)]"
                      : "text-[var(--success)]";

                return (
                  <tr key={item.id} className="border-b border-[rgba(152,164,189,0.08)] align-top">
                    <td className="px-5 py-4">
                      <div className="max-w-[20rem]">
                        <p className="text-base font-semibold">{item.name}</p>
                        <p className="mt-1 text-sm text-[var(--text-secondary)] line-clamp-2">
                          {item.description || "No note has been added for this product yet."}
                        </p>
                      </div>
                    </td>
                    <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                      {item.category || "Uncategorized"}
                    </td>
                    <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                      {item.sku || "No SKU"}
                    </td>
                    <td className={`px-5 py-4 text-sm font-semibold ${tone}`}>
                      {item.stock_on_hand}
                    </td>
                    <td className="px-5 py-4 text-sm text-[var(--text-primary)]">
                      {formatCurrency(Number(item.sell_price), currencyCode)}
                    </td>
                    {showSupplierColumn ? (
                      <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                        {item.supplier_id || "Not linked"}
                      </td>
                    ) : null}
                    {showPurchaseColumn ? (
                      <td className="px-5 py-4 text-sm text-[var(--text-secondary)]">
                        {item.last_purchase_date || "Not tracked"}
                      </td>
                    ) : null}
                    <td className="px-5 py-4">
                      <span className="rounded-full border border-[rgba(152,164,189,0.12)] bg-[rgba(13,18,28,0.8)] px-3 py-1 text-xs font-medium text-[var(--text-secondary)]">
                        {item.status}
                      </span>
                    </td>
                  </tr>
                );
              })
            ) : (
              <tr>
                <td
                  colSpan={columnCount}
                  className="px-5 py-10 text-center text-sm text-[var(--text-secondary)]"
                >
                  No products are available for this store yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
