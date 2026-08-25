"use client";

import { useMemo, useState } from "react";
import { Activity, PackageX, ShoppingBasket, Users } from "lucide-react";

import { BusinessPulse } from "@/components/business-pulse";
import { DeadStock } from "@/components/dead-stock";
import { ReorderList } from "@/components/reorder-list";
import { StaffPerformance } from "@/components/staff-performance";
import { DateRangePicker } from "@/components/ui/date-range-picker";
import { shopDateKey } from "@/lib/dashboard-metrics";
import { resolveRange, toReportWindow } from "@/lib/date-ranges";
import type { DateRange, RangeKey } from "@/lib/date-ranges";

type TabKey = "pulse" | "dead-stock" | "reorder" | "staff";

const TABS: { key: TabKey; label: string; icon: typeof Activity; hint: string }[] = [
  { key: "pulse", label: "Report", icon: Activity, hint: "Money kept, and what earned it" },
  { key: "dead-stock", label: "Dead stock", icon: PackageX, hint: "Cash sitting on the shelf" },
  { key: "reorder", label: "Buying list", icon: ShoppingBasket, hint: "What to reorder today" },
  { key: "staff", label: "Team", icon: Users, hint: "Who is selling, and how" },
];

/** Which tabs a date window actually means something for.
 *
 *  Dead stock asks "unsold for how long", which is a different question from
 *  "between these dates" and keeps its own control. The buying list is what
 *  to order today and has no window at all. Offering a date filter on either
 *  would be showing a control that quietly does nothing.
 */
const TABS_WITH_RANGE: TabKey[] = ["pulse", "staff"];


export function InsightsTabs({
  shopName,
  timeZone = "Asia/Kolkata",
}: {
  shopName: string;
  timeZone?: string;
}) {
  const [tab, setTab] = useState<TabKey>("pulse");
  const [rangeKey, setRangeKey] = useState<RangeKey>("last30");
  const [custom, setCustom] = useState<DateRange>({ from: "", to: "" });

  const today = useMemo(() => shopDateKey(new Date(), timeZone), [timeZone]);
  const range = useMemo(
    () => resolveRange(rangeKey, today, custom),
    [rangeKey, today, custom],
  );

  const reportWindow = useMemo(() => toReportWindow(range), [range]);

  const active = TABS.find((t) => t.key === tab) ?? TABS[0];
  const showRange = TABS_WITH_RANGE.includes(tab);

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-5">
      {/* One control row: which report on the left, the window it covers on
          the right. relative z-20 because the fade animates a transform,
          which traps the date menu inside this card's stacking context. */}
      <div className="relative z-20 rounded-2xl border border-[var(--border-soft)] bg-[var(--surface)] p-3 shadow-sm animate-fade-in-up">
        <div className="flex flex-wrap items-center gap-2.5">
          <div className="no-scrollbar flex min-w-0 items-center gap-1 overflow-x-auto rounded-xl border border-[var(--border-soft)] bg-[var(--bg-base)] p-1">
            {TABS.map(({ key, label, icon: Icon }) => (
              <button
                key={key}
                type="button"
                onClick={() => setTab(key)}
                aria-pressed={tab === key}
                className={`focus-ring inline-flex shrink-0 cursor-pointer items-center gap-1.5 whitespace-nowrap rounded-lg px-3.5 py-1.5 text-xs font-bold transition-colors ${
                  tab === key
                    ? "border border-[var(--primary)]/25 bg-[var(--primary)]/12 text-[var(--primary-dark)] shadow-sm"
                    : "border border-transparent text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
                }`}
              >
                <Icon className="h-3.5 w-3.5" />
                {label}
              </button>
            ))}
          </div>

          <span className="text-[11.5px] font-semibold text-[var(--text-tertiary)]">
            {active.hint}
          </span>

          {showRange && (
            <DateRangePicker
              value={rangeKey}
              custom={custom}
              today={today}
              onChange={(key, next) => {
                setRangeKey(key);
                setCustom(next);
              }}
              className="ml-auto w-[190px] shrink-0"
            />
          )}
        </div>
      </div>

      {tab === "pulse" && <BusinessPulse range={reportWindow} />}
      {tab === "dead-stock" && <DeadStock />}
      {tab === "reorder" && <ReorderList shopName={shopName} />}
      {tab === "staff" && <StaffPerformance range={reportWindow} />}
    </div>
  );
}
