"use client";

/** The delivery editor, shared by every screen that books a purchase.
 *
 *  It was written once inside Purchase orders and lived only there, so the
 *  Suppliers screen booked bills a different way - one summary line, no stock
 *  item - and a delivery entered on that screen moved no stock, rewrote no
 *  cost price and never reached the price history. Same shop, same delivery,
 *  a different set of records depending on which screen was open.
 *
 *  Lifting it here makes that impossible: both screens send the same lines,
 *  so one entry updates stock, cost price, last supplier, the supplier ledger
 *  and the price history together.
 */
import { Plus, Trash2, X } from "lucide-react";

import { formatCurrency } from "@/lib/formatters";
import {
  BLANK_LINE,
  type DraftLine,
  type StockItem,
  applyPick,
  lineTotal,
  matchesFor,
} from "@/lib/item-lines";
import { packIsComplete, packSummary, packToUnitCost, packsToUnits } from "@/lib/pack-maths";
import { formatQuantity } from "@/lib/utils";

type Props = {
  items: StockItem[];
  lines: DraftLine[];
  onChange: (lines: DraftLine[]) => void;
  /** Which row has its picker open. Held by the parent so a click anywhere
   *  else on the form can close it. */
  openLine: number | null;
  onOpenLine: (index: number | null) => void;
  /** "Arrived" when stock is moving now, "Qty" when it is a request. */
  quantityLabel?: string;
};

export function ItemLinesEditor({
  items,
  lines,
  onChange,
  openLine,
  onOpenLine,
  quantityLabel = "Qty",
}: Props) {
  const updateLine = (index: number, patch: Partial<DraftLine>) =>
    onChange(lines.map((l, i) => (i === index ? { ...l, ...patch } : l)));

  return (
    <div className="space-y-2.5">
      {lines.map((line, index) => {
        const picked = items.find((it) => it.id === line.itemId) ?? null;
        const unitLabel = picked?.unit?.trim() || "units";
        const packEntry = {
          packs: line.packs,
          unitsPerPack: line.unitsPerPack,
          packCost: line.packCost,
        };
        const total = lineTotal(line);
        return (
          <div
            key={index}
            className="rounded-[12px] border border-[var(--border-soft)] bg-[var(--bg-base)] p-3"
          >
            <div className="flex flex-wrap items-center gap-2">
              {/* Type to find. A native select over two hundred and eighty
                  products is a list nobody can reach the end of. */}
              <div className="relative min-w-[200px] flex-1">
                <input
                  type="text"
                  value={picked ? picked.name : (line.query ?? "")}
                  onChange={(e) => updateLine(index, { query: e.target.value, itemId: "" })}
                  onFocus={() => onOpenLine(index)}
                  placeholder="Type an item name or SKU"
                  className="w-full rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2 text-[12.5px] font-semibold text-[var(--text-primary)] outline-none focus:border-[var(--primary)]"
                />
                {picked && (
                  <button
                    type="button"
                    onClick={() => updateLine(index, { itemId: "", query: "" })}
                    aria-label="Choose a different item"
                    className="focus-ring absolute right-2 top-1/2 grid h-6 w-6 -translate-y-1/2 cursor-pointer place-items-center rounded-full text-[var(--text-tertiary)] hover:text-[var(--text-primary)]"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                )}

                {openLine === index && !picked && (
                  <div
                    onMouseDown={(e) => e.stopPropagation()}
                    className="animate-fade-in-up absolute left-0 right-0 top-full z-30 mt-1 max-h-[200px] overflow-y-auto rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] p-1 shadow-lg"
                  >
                    {matchesFor(items, line.query ?? "").map((it) => (
                      <button
                        key={it.id}
                        type="button"
                        onClick={() => updateLine(index, applyPick(line, it))}
                        className="focus-ring flex w-full cursor-pointer items-center gap-2 rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-[var(--bg-base)]"
                      >
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-[12px] font-bold text-[var(--text-primary)]">
                            {it.name}
                            {it.size ? ` (${it.size})` : ""}
                          </span>
                          <span className="block truncate font-mono text-[10px] text-[var(--text-tertiary)]">
                            {formatQuantity(it.stock)} {it.unit?.trim() || "in stock"}
                            {it.costPrice != null ? ` · last ${it.costPrice}` : " · no cost yet"}
                          </span>
                        </span>
                      </button>
                    ))}
                    {matchesFor(items, line.query ?? "").length === 0 && (
                      <p className="m-0 px-2.5 py-3 text-[11.5px] font-semibold text-[var(--text-tertiary)]">
                        Nothing in stock matches that. Add it in Stock first.
                      </p>
                    )}
                  </div>
                )}
              </div>

              <label className="flex items-center gap-1.5">
                <span className="sr-only">Quantity</span>
                <input
                  type="number"
                  min="0"
                  step="any"
                  placeholder={quantityLabel}
                  value={line.quantity}
                  onChange={(e) => updateLine(index, { quantity: e.target.value })}
                  className="tnum w-24 rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2 font-mono text-[13px] font-bold text-[var(--text-primary)] outline-none focus:border-[var(--primary)]"
                />
                {/* The unit, said out loud. Whether 50 means fifty kilos or
                    fifty sacks is the whole question. */}
                <span className="text-[11px] font-bold text-[var(--text-tertiary)]">
                  {unitLabel}
                </span>
              </label>

              <label className="flex items-center gap-1.5">
                <span className="sr-only">Cost per unit</span>
                <input
                  type="number"
                  min="0"
                  step="any"
                  placeholder="Cost"
                  value={line.unitCost}
                  onChange={(e) => updateLine(index, { unitCost: e.target.value })}
                  className="tnum w-28 rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2 font-mono text-[13px] font-bold text-[var(--text-primary)] outline-none focus:border-[var(--primary)]"
                />
                <span className="whitespace-nowrap text-[11px] font-bold text-[var(--text-tertiary)]">
                  per {unitLabel}
                </span>
              </label>

              {total > 0 && (
                <span className="tnum ml-auto font-mono text-[13px] font-bold text-[var(--text-primary)]">
                  {formatCurrency(total)}
                </span>
              )}

              {lines.length > 1 && (
                <button
                  type="button"
                  aria-label="Remove item"
                  onClick={() => onChange(lines.filter((_, i) => i !== index))}
                  className="focus-ring cursor-pointer rounded-lg p-2 text-[var(--text-tertiary)] hover:text-[var(--error-strong)]"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              )}
            </div>

            {/* The bag question, answered by arithmetic instead of by the
                shopkeeper. Stock is kept in the selling unit, so a 50kg sack
                entered as "1" makes the app believe it holds one kilo. Enter
                the delivery as it came and this fills the two fields above. */}
            <div className="mt-2 border-t border-[var(--border-soft)] pt-2">
              {!line.packMode ? (
                <button
                  type="button"
                  onClick={() => updateLine(index, { packMode: true })}
                  className="focus-ring cursor-pointer text-[11.5px] font-bold text-[var(--primary-hover)] hover:underline"
                >
                  + It came in bags, boxes or cases
                </button>
              ) : (
                <div className="flex flex-wrap items-end gap-2">
                  {[
                    { key: "packs" as const, label: "Packs", placeholder: "2", width: "w-20" },
                    {
                      key: "unitsPerPack" as const,
                      label: `${unitLabel} in one`,
                      placeholder: "50",
                      width: "w-24",
                    },
                    {
                      key: "packCost" as const,
                      label: "Cost of one",
                      placeholder: "2000",
                      width: "w-28",
                    },
                  ].map((field) => (
                    <label key={field.key} className="flex flex-col gap-1">
                      <span className="font-mono text-[9.5px] font-bold uppercase tracking-[0.12em] text-[var(--text-tertiary)]">
                        {field.label}
                      </span>
                      <input
                        type="number"
                        min="0"
                        step="any"
                        placeholder={field.placeholder}
                        value={line[field.key]}
                        onChange={(e) => updateLine(index, { [field.key]: e.target.value })}
                        className={`tnum ${field.width} rounded-[10px] border border-[var(--border-soft)] bg-[var(--surface)] px-3 py-2 font-mono text-[13px] font-bold text-[var(--text-primary)] outline-none focus:border-[var(--primary)]`}
                      />
                    </label>
                  ))}

                  <button
                    type="button"
                    disabled={!packIsComplete(packEntry)}
                    onClick={() => {
                      const cost = packToUnitCost(packEntry);
                      updateLine(index, {
                        quantity: String(packsToUnits(packEntry)),
                        unitCost: cost === null ? "" : String(cost),
                        packMode: false,
                      });
                    }}
                    className="focus-ring cursor-pointer rounded-[10px] border border-[var(--primary)]/25 bg-[var(--primary)]/12 px-3 py-2 text-[12px] font-extrabold text-[var(--primary-dark)] transition-colors hover:bg-[var(--primary)]/20 disabled:cursor-not-allowed disabled:opacity-50"
                  >
                    Use this
                  </button>

                  {/* Shown before it is applied, so a wrong pack size is
                      caught here rather than in the stock figures. */}
                  <span className="text-[11.5px] font-semibold text-[var(--text-tertiary)]">
                    {packSummary(packEntry, unitLabel) || "Fill all three to work it out"}
                  </span>
                </div>
              )}
            </div>
          </div>
        );
      })}

      <button
        type="button"
        onClick={() => onChange([...lines, { ...BLANK_LINE }])}
        className="inline-flex cursor-pointer items-center gap-1.5 text-xs font-extrabold text-[var(--primary)] hover:underline"
      >
        <Plus className="h-3.5 w-3.5" /> Add another item
      </button>
    </div>
  );
}
