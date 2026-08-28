// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";

/** Does the till actually go and fetch the rest of the shop?
 *
 *  The paging fix was written, reviewed, committed and never ran. The function
 *  holding it was declared inside a `useEffect` whose body ended without
 *  calling it — one missing line, no type error, no lint error, and 1,391
 *  passing tests, because every test exercised the mapping and none of them
 *  exercised the mount.
 *
 *  Measured in a browser afterwards: zero requests to /api/inventory, 199
 *  tiles from the server prop, and a product with 228 in stock answering
 *  "Nothing matches" to a search for its own name.
 *
 *  So this test asserts behaviour rather than shape. It renders the till and
 *  watches the network: the request has to happen, and it has to keep going
 *  until the cursor runs out. A future refactor that leaves the loader
 *  correct but unreferenced fails here.
 */

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn(), replace: vi.fn(), push: vi.fn() }),
}));

const PAGE_SIZE = 100;
const CATALOGUE = 285;

/** A product as the inventory API returns it. */
function row(index: number) {
  return {
    id: `item-${index}`,
    name: index === CATALOGUE - 1 ? "Tata Tea dozen" : `Product ${index}`,
    sku: `SKU-${index}`,
    sell_price: "10.00",
    stock_on_hand: index === CATALOGUE - 1 ? 228 : 5,
    status: "active",
  };
}

/** Pages a list the way the real API does: a bare array, and the next page
 *  named in a header rather than in the body. */
function pageOf(all: unknown[], cursor: string | null) {
  const start = cursor ? Number(cursor) : 0;
  const slice = all.slice(start, start + PAGE_SIZE);
  const next = start + PAGE_SIZE;
  const headers = new Headers();
  if (next < all.length) headers.set("X-Next-Cursor", String(next));
  return new Response(JSON.stringify(slice), { status: 200, headers });
}

const products = Array.from({ length: CATALOGUE }, (_, index) => row(index));

let inventoryRequests: string[] = [];
let customerRequests: string[] = [];

beforeEach(() => {
  inventoryRequests = [];
  customerRequests = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      const cursor = new URL(url, "http://localhost").searchParams.get("cursor");

      if (url.startsWith("/api/inventory")) {
        inventoryRequests.push(url);
        return pageOf(products, cursor);
      }
      if (url.startsWith("/api/customers")) {
        customerRequests.push(url);
        return pageOf([], cursor);
      }
      if (url.startsWith("/api/settings")) {
        return new Response(JSON.stringify({ features: {} }), { status: 200 });
      }
      return new Response("[]", { status: 200 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

async function renderTill() {
  const { PosTerminal } = await import("./pos-terminal");
  const { DialogProvider } = await import("./ui/dialog-provider");
  render(
    <DialogProvider>
      <PosTerminal
        shopId="shop-1"
        initialInventory={products.slice(0, 199)}
        initialCustomers={[]}
      />
    </DialogProvider>,
  );
}

describe("the till loading the catalogue", () => {
  it("asks the server for the catalogue at all", async () => {
    // The whole finding. Before the fix this array stayed empty: the till
    // showed the server-rendered first page and never went back for more.
    await renderTill();

    await waitFor(() => expect(inventoryRequests.length).toBeGreaterThan(0));
  });

  it("follows the cursor past the first page", async () => {
    await renderTill();

    await waitFor(() => {
      expect(inventoryRequests.some((url) => url.includes("cursor="))).toBe(true);
    });
  });

  it("keeps going until the whole shop is loaded", async () => {
    // 285 products at 100 a page is three requests. Two would mean the till
    // silently cannot sell the last 85.
    await renderTill();

    await waitFor(() => expect(inventoryRequests.length).toBe(3));
  });

  it("can find a product that lives past the first page", async () => {
    // The shopkeeper's version of the same question, and the one they
    // actually asked: searching for a product with 228 on the shelf was
    // answered with "Nothing matches".
    await renderTill();

    await waitFor(
      () => expect(screen.getAllByText("Tata Tea dozen").length).toBeGreaterThan(0),
      { timeout: 3000 },
    );
  });

  it("loads the customer list too", async () => {
    // The same dead function held both. A khata sale to somebody past the
    // first page of customers was attributed to Walk-in Guest, and the debt
    // was recorded against nobody.
    await renderTill();

    await waitFor(() => expect(customerRequests.length).toBeGreaterThan(0));
  });
});
