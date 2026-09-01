// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";

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
    //
    // Typed rather than looked for in the grid, because the grid is capped at
    // a hundred tiles now and this product is the 285th. That cap is exactly
    // why the search has to reach past what is drawn - the two changes have
    // to hold together, and this test is where they meet.
    await renderTill();
    await waitFor(() => expect(inventoryRequests.length).toBe(3));

    const search = await screen.findByPlaceholderText(/Scan barcode or search/i);
    fireEvent.change(search, { target: { value: "Tata Tea" } });

    await waitFor(
      () => expect(screen.getAllByText("Tata Tea dozen").length).toBeGreaterThan(0),
      { timeout: 3000 },
    );
  });

  it("draws a screenful rather than the whole shop", async () => {
    // The lag. Five thousand products became five thousand tiles, each with
    // an image, before the cashier had typed anything.
    //
    // Asked as "is the 151st product in the document", because counting
    // rendered nodes turned out to be a test that passed with the cap taken
    // out - it measured nothing. This one names a product past the cap and
    // asks whether it is there.
    await renderTill();
    await waitFor(() => expect(inventoryRequests.length).toBe(3));

    expect(screen.queryByText("Product 150")).toBeNull();
    // ...and one inside it is, so the cap is a cap and not a broken grid.
    expect(screen.queryByText("Product 5")).not.toBeNull();
  });

  it("still finds a capped-out product when it is searched for", async () => {
    // The cap must never become the paging bug in a new costume.
    await renderTill();
    await waitFor(() => expect(inventoryRequests.length).toBe(3));

    const search = await screen.findByPlaceholderText(/Scan barcode or search/i);
    fireEvent.change(search, { target: { value: "Product 150" } });

    await waitFor(() => expect(screen.queryByText("Product 150")).not.toBeNull());
  });

  it("says how many matched, so a cap is never mistaken for an empty shop", async () => {
    // The whole reason the paging defect survived a shop floor was that
    // nothing on screen was wrong - there was simply less of it.
    await renderTill();

    await waitFor(() =>
      expect(screen.getByText(/Showing 100 of 285/)).toBeTruthy(),
    );
  });

  it("loads the customer list too", async () => {
    // The same dead function held both. A khata sale to somebody past the
    // first page of customers was attributed to Walk-in Guest, and the debt
    // was recorded against nobody.
    await renderTill();

    await waitFor(() => expect(customerRequests.length).toBeGreaterThan(0));
  });

  it("says so when the shop is bigger than it can load", async () => {
    // The ceiling is 25 pages of 200 rows, and a real shop of about five
    // thousand products is sitting on it. Past that the till holds most of
    // the shop and looks exactly like it holds all of it - which is the
    // original defect, one order of magnitude further out.
    let issued = 0;
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.startsWith("/api/settings")) {
          return new Response(JSON.stringify({ features: {} }), { status: 200 });
        }
        if (url.startsWith("/api/inventory")) {
          issued += 1;
          const headers = new Headers({ "X-Next-Cursor": `c-${issued}` });
          return new Response(JSON.stringify([row(issued)]), { status: 200, headers });
        }
        return new Response("[]", { status: 200 });
      }),
    );

    await renderTill();

    await waitFor(
      () => expect(screen.getByText(/too large to load in full/i)).toBeTruthy(),
      { timeout: 5000 },
    );
  });

  it("stays quiet when the whole shop did load", async () => {
    // A warning that shows on every ordinary shop is a warning nobody reads.
    await renderTill();
    await waitFor(() => expect(inventoryRequests.length).toBe(3));

    expect(screen.queryByText(/too large to load in full/i)).toBeNull();
  });
});
