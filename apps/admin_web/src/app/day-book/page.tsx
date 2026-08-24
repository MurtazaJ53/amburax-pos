import { AdminShell } from "@/components/admin-shell";
import { DayBook } from "@/components/day-book";
import { EmptyState } from "@/components/empty-state";
import { getSession, resolveActiveShop } from "@/lib/admin-api";

export const metadata = {
  title: "Day Book (Roj Mel) | Business Hub",
  description: "What came in today, and what went out on credit",
};

export default async function DayBookPage() {
  const session = await getSession();
  const activeShop = resolveActiveShop(session);

  return (
    <AdminShell
      session={session}
      activeShop={activeShop}
      activeRoute="day-book"
      title="Day book"
      subtitle="Jama and Udhaar for the day, in the form the paper book already uses."
    >
      {!activeShop ? (
        <EmptyState
          title="No shop membership found"
          body="This account is signed in, but there is no active shop membership yet."
        />
      ) : (
        <DayBook
          upiVpa={activeShop.shop.upi_vpa ?? ""}
          // The book must open on the shop's date, not the server's.
          timeZone={activeShop.shop.timezone || "Asia/Kolkata"}
        />
      )}
    </AdminShell>
  );
}
