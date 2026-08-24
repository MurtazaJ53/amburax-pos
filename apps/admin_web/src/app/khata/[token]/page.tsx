import { AlertCircle, Store } from "lucide-react";

/**
 * The one page in this app with no sign-in.
 *
 * A customer opens it from a WhatsApp reminder to see what they owe and pay.
 * It deliberately does NOT call getSession(): doing so would redirect them to
 * a login screen for an account they will never have.
 *
 * Rendered server-side against the API directly rather than through a /api
 * proxy route, because there is no session cookie to attach — the token in the
 * URL is the whole credential.
 */
const API_BASE_URL =
  process.env.BUSINESS_HUB_API_BASE_URL?.replace(/\/$/, "") ??
  "http://127.0.0.1:8000/api/v1";

type StatementEntry = {
  occurred_at: string;
  event_type: string;
  amount: string;
  note: string;
};

type Statement = {
  customer_name: string;
  shop: { name: string; phone: string };
  balance: string;
  currency_code: string;
  upi_link: string | null;
  entries: StatementEntry[];
  expires_at: string;
};

export const metadata = {
  title: "Your khata balance",
  // No indexing: these URLs are credentials.
  robots: { index: false, follow: false },
};

function money(amount: string | number, currency: string): string {
  const value = typeof amount === "number" ? amount : parseFloat(String(amount ?? "0"));
  const safe = Number.isFinite(value) ? value : 0;
  try {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: currency || "INR",
      maximumFractionDigits: 2,
    }).format(safe);
  } catch {
    return `₹${safe.toFixed(2)}`;
  }
}

function entryLabel(type: string): string {
  switch (type) {
    case "sale":
      return "Purchase";
    case "payment":
      return "Payment received";
    case "opening_balance":
      return "Opening balance";
    case "adjustment":
      return "Adjustment";
    default:
      return "Entry";
  }
}

async function loadStatement(token: string): Promise<Statement | null> {
  try {
    const res = await fetch(
      `${API_BASE_URL}/public/khata/${encodeURIComponent(token)}/`,
      { cache: "no-store" },
    );
    if (!res.ok) return null;
    return (await res.json()) as Statement;
  } catch {
    return null;
  }
}

export default async function KhataStatementPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const statement = await loadStatement(token);

  if (!statement) {
    return (
      <main className="min-h-screen flex items-center justify-center bg-[var(--bg-app)] p-6">
        <div className="w-full max-w-sm rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-6 text-center shadow-sm">
          <AlertCircle className="w-8 h-8 mx-auto text-[var(--warning-strong)]" />
          <h1 className="mt-3 text-base font-black text-[var(--text-primary)]">
            This link is no longer valid
          </h1>
          <p className="mt-2 text-xs font-semibold text-[var(--text-secondary)]">
            Statement links expire for your safety. Please ask the shop to send
            you a new one.
          </p>
        </div>
      </main>
    );
  }

  const balance = parseFloat(statement.balance) || 0;
  const owes = balance > 0;

  return (
    <main className="min-h-screen bg-[var(--bg-app)] px-4 py-8">
      <div className="mx-auto w-full max-w-md space-y-5">
        <header className="text-center">
          <div className="mx-auto w-12 h-12 rounded-2xl bg-[var(--primary)]/10 flex items-center justify-center">
            <Store className="w-6 h-6 text-[var(--primary-hover)]" />
          </div>
          <h1 className="mt-3 text-lg font-black text-[var(--text-primary)]">
            {statement.shop.name}
          </h1>
          <p className="text-xs font-bold text-[var(--text-secondary)]">
            Khata statement for {statement.customer_name}
          </p>
        </header>

        <section
          className={`rounded-[24px] p-6 text-center shadow-md ${
            owes
              ? "bg-gradient-to-br from-[var(--primary-light)] to-[var(--primary-hover)] text-white"
              : "border border-[var(--border-soft)] bg-[var(--surface)]"
          }`}
        >
          <span
            className={`text-[10px] font-extrabold uppercase tracking-[0.12em] ${
              owes ? "text-[var(--text-primary)]/80" : "text-[var(--text-tertiary)]"
            }`}
          >
            {owes ? "Amount due" : "Your balance"}
          </span>
          <p
            className={`mt-1 text-3xl font-[900] tracking-tight ${
              owes ? "" : "text-[var(--success-strong)]"
            }`}
          >
            {money(balance, statement.currency_code)}
          </p>
          {!owes && (
            <p className="mt-1 text-xs font-bold text-[var(--text-secondary)]">
              Nothing outstanding. Thank you!
            </p>
          )}
        </section>

        {statement.upi_link && (
          <a
            href={statement.upi_link}
            className="block w-full rounded-2xl bg-[var(--success)] px-6 py-4 text-center text-sm font-extrabold text-white shadow-md"
          >
            Pay {money(balance, statement.currency_code)} by UPI
          </a>
        )}

        {statement.entries.length > 0 && (
          <section className="rounded-[24px] border border-[var(--border-soft)] bg-[var(--surface)] p-5 shadow-sm">
            <h2 className="text-sm font-extrabold text-[var(--text-primary)]">
              Recent entries
            </h2>
            <div className="mt-3.5 space-y-3">
              {statement.entries.map((entry, index) => {
                const amount = parseFloat(entry.amount) || 0;
                // A negative delta reduces what is owed: money the shop
                // received. Showing it as "-500" would read as a new charge.
                const isPayment = amount < 0;
                return (
                  <div
                    key={`${entry.occurred_at}-${index}`}
                    className="flex items-start justify-between gap-3 border-b border-[var(--border-soft)] pb-3 last:border-0 last:pb-0"
                  >
                    <div className="min-w-0">
                      <span className="block text-xs font-extrabold text-[var(--text-primary)]">
                        {entryLabel(entry.event_type)}
                      </span>
                      <span className="block text-[10px] font-semibold text-[var(--text-tertiary)] mt-0.5">
                        {new Date(entry.occurred_at).toLocaleDateString("en-IN", {
                          day: "numeric",
                          month: "short",
                          year: "numeric",
                        })}
                        {entry.note ? ` · ${entry.note}` : ""}
                      </span>
                    </div>
                    <span
                      className={`shrink-0 text-xs font-black ${
                        isPayment
                          ? "text-[var(--success-strong)]"
                          : "text-[var(--text-primary)]"
                      }`}
                    >
                      {isPayment ? "− " : "+ "}
                      {money(Math.abs(amount), statement.currency_code)}
                    </span>
                  </div>
                );
              })}
            </div>
          </section>
        )}

        <footer className="text-center space-y-1 pb-4">
          {statement.shop.phone && (
            <p className="text-[11px] font-bold text-[var(--text-secondary)]">
              Questions? Call the shop on {statement.shop.phone}
            </p>
          )}
          <p className="text-[10px] font-semibold text-[var(--text-tertiary)]">
            This link is private to you and expires on{" "}
            {new Date(statement.expires_at).toLocaleDateString("en-IN")}.
          </p>
        </footer>
      </div>
    </main>
  );
}
