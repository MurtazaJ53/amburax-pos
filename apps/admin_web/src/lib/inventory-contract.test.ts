import { readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

/** The web client and the Django serializer have to agree on field names, and
 *  nothing at runtime checks that they do.
 *
 *  DRF silently ignores a field it does not accept and still answers 200, so
 *  sending the wrong name loses the value with no error anywhere: the shop
 *  types a cost of 120, the save "succeeds", and the cost comes back empty.
 *  That is exactly what happened with cost_price, so the contract is pinned
 *  here by reading both sides. */

function read(path: string): string {
  // core.autocrlf gives CRLF on a Windows checkout; normalise so the matching
  // below behaves the same on every machine.
  return readFileSync(path, "utf8").replace(/\r\n/g, "\n");
}

const SERIALIZER = read(
  join(__dirname, "../../../backend/platform_apps/inventory/serializers.py"),
);
const MANAGER = read(join(__dirname, "../components/inventory-manager.tsx"));

describe("who owns the cost price field", () => {
  it("has cost_price as read-only on the server", () => {
    // A SerializerMethodField cannot be written to. If this ever stops being
    // true the client may send cost_price again.
    expect(SERIALIZER).toMatch(/cost_price\s*=\s*serializers\.SerializerMethodField\(\)/);
  });

  it("names the writable field private_cost_price", () => {
    expect(SERIALIZER).toMatch(/private_cost_price\s*=\s*serializers\.DecimalField\(/);
    expect(SERIALIZER).toMatch(/source="cost_price_input"/);
  });

  it("has the web client send the writable name, not the read-only one", () => {
    expect(MANAGER).toContain("private_cost_price:");
  });

  it("never sends the read-only name in a request body", () => {
    // Reading item.cost_price is fine and expected; writing "cost_price:" into
    // a payload object is the mistake being guarded against.
    const payloadWrites = MANAGER.match(/^\s+cost_price:/gm) ?? [];
    expect(payloadWrites).toEqual([]);
  });
});

describe("fields the screen relies on staying on the wire", () => {
  for (const field of [
    "reorder_level",
    "gst_rate",
    "hsn_code",
    "unit",
    "price_includes_tax",
    "image_data",
    "stock_on_hand",
  ]) {
    it(`still serialises ${field}`, () => {
      expect(SERIALIZER).toContain(`"${field}"`);
    });
  }
});
