"use client";

import { useState } from "react";
import { Gift, HandCoins, Users } from "lucide-react";

import { CustomersKhata } from "@/components/customers-khata";
import { KhataCollection } from "@/components/khata-collection";
import { LoyaltySettings } from "@/components/loyalty-settings";
import type { Customer, CustomerSummaryPayload } from "@/lib/types";

type TabKey = "customers" | "collection" | "loyalty";

const TABS: { key: TabKey; label: string; icon: typeof Users }[] = [
  { key: "customers", label: "Customers", icon: Users },
  { key: "collection", label: "Collection", icon: HandCoins },
  { key: "loyalty", label: "Loyalty", icon: Gift },
];

export function CustomersTabs({
  initialCustomers,
  initialSummary,
  shopId,
  shopName,
  upiVpa,
}: {
  initialCustomers: Customer[];
  initialSummary: CustomerSummaryPayload;
  shopId: string;
  shopName: string;
  upiVpa: string;
}) {
  const [tab, setTab] = useState<TabKey>("customers");

  return (
    <div className="flex min-h-0 flex-1 flex-col gap-4">
      <div className="flex flex-wrap gap-2">
        {TABS.map(({ key, label, icon: Icon }) => (
          <button
            key={key}
            type="button"
            onClick={() => setTab(key)}
            className={`inline-flex items-center gap-2 rounded-2xl border px-4 py-2.5 text-xs font-extrabold transition-colors ${
              tab === key
                ? "border-[var(--primary)] bg-[var(--primary)]/10 text-[var(--primary-hover)]"
                : "border-border-soft bg-surface text-text-secondary hover:text-text-primary"
            }`}
          >
            <Icon className="w-3.5 h-3.5" />
            {label}
          </button>
        ))}
      </div>

      {tab === "customers" && (
        <CustomersKhata
          initialCustomers={initialCustomers}
          initialSummary={initialSummary}
          shopId={shopId}
        />
      )}
      {tab === "collection" && (
        <KhataCollection shopName={shopName} upiVpa={upiVpa} />
      )}
      {tab === "loyalty" && <LoyaltySettings />}
    </div>
  );
}
