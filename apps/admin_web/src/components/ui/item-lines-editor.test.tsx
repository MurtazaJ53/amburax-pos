/**
 * @vitest-environment happy-dom
 *
 * The editor both buying screens share.
 *
 * item-lines.test.ts pins the rules; this pins that the screen actually
 * applies them. The two failures that matter here are the ones that produce
 * a bill totalling correctly against stock that never moved: an item that
 * looks chosen but is not, and a sack entered as one unit.
 */
import { afterEach, describe, expect, it } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { useState } from "react";

import { BLANK_LINE, type DraftLine, type StockItem } from "@/lib/item-lines";

import { ItemLinesEditor } from "./item-lines-editor";

afterEach(cleanup);

const ITEMS: StockItem[] = [
  { id: "i1", name: "Basmati Rice", sku: "RICE-01", size: "5kg", unit: "kg", costPrice: 40, stock: 12 },
  { id: "i2", name: "Toor Dal", sku: "DAL-01", size: "", unit: "kg", costPrice: null, stock: 0 },
];

/** The editor is controlled, so a host has to hold the lines for it. */
function Host({ items = ITEMS }: { items?: StockItem[] }) {
  const [lines, setLines] = useState<DraftLine[]>([{ ...BLANK_LINE }]);
  const [openLine, setOpenLine] = useState<number | null>(null);
  return (
    <ItemLinesEditor
      items={items}
      lines={lines}
      onChange={setLines}
      openLine={openLine}
      onOpenLine={setOpenLine}
    />
  );
}

const itemBox = () => screen.getAllByPlaceholderText("Type an item name or SKU")[0];
const costBox = () => screen.getAllByPlaceholderText("Cost")[0] as HTMLInputElement;
const qtyBox = () => screen.getAllByPlaceholderText("Qty")[0] as HTMLInputElement;

function openPicker() {
  fireEvent.focus(itemBox());
}

describe("choosing an item", () => {
  it("lists what is in stock as soon as the box is focused", () => {
    // Browsing, not searching. An empty list here reads as an empty shop.
    render(<Host />);
    openPicker();
    expect(screen.getByText("Basmati Rice (5kg)")).toBeTruthy();
    expect(screen.getByText("Toor Dal")).toBeTruthy();
  });

  it("narrows the list as a name is typed", () => {
    render(<Host />);
    openPicker();
    fireEvent.change(itemBox(), { target: { value: "dal" } });
    expect(screen.queryByText("Basmati Rice (5kg)")).toBeNull();
    expect(screen.getByText("Toor Dal")).toBeTruthy();
  });

  it("fills the cost it was last bought at", () => {
    render(<Host />);
    openPicker();
    fireEvent.click(screen.getByText("Basmati Rice (5kg)"));
    expect(costBox().value).toBe("40");
  });

  it("fills no cost for an item never bought before", () => {
    // A zero here would become the cost price of everything received.
    render(<Host />);
    openPicker();
    fireEvent.click(screen.getByText("Toor Dal"));
    expect(costBox().value).toBe("");
  });

  it("shows the item's own unit, so a quantity means something", () => {
    render(<Host />);
    openPicker();
    fireEvent.click(screen.getByText("Basmati Rice (5kg)"));
    expect(screen.getAllByText("kg").length).toBeGreaterThan(0);
  });

  it("says where to go when nothing matches, rather than showing an empty box", () => {
    render(<Host />);
    openPicker();
    fireEvent.change(itemBox(), { target: { value: "zzz" } });
    expect(screen.getByText(/Nothing in stock matches that/)).toBeTruthy();
  });

  it("lets a wrong choice be undone", () => {
    render(<Host />);
    openPicker();
    fireEvent.click(screen.getByText("Basmati Rice (5kg)"));
    fireEvent.click(screen.getByLabelText("Choose a different item"));
    expect((itemBox() as HTMLInputElement).value).toBe("");
  });
});

describe("the bag question", () => {
  it("turns a delivery of sacks into units and a unit cost", () => {
    // Stock is kept in the selling unit, so two 50kg sacks at 2000 each is
    // 100 kg at 40 - not two of anything. Entered as "2" the app would
    // believe it holds two kilos.
    render(<Host />);
    openPicker();
    fireEvent.click(screen.getByText("Basmati Rice (5kg)"));

    fireEvent.click(screen.getByText(/It came in bags, boxes or cases/));
    fireEvent.change(screen.getByPlaceholderText("2"), { target: { value: "2" } });
    fireEvent.change(screen.getByPlaceholderText("50"), { target: { value: "50" } });
    fireEvent.change(screen.getByPlaceholderText("2000"), { target: { value: "2000" } });

    fireEvent.click(screen.getByText("Use this"));

    expect(qtyBox().value).toBe("100");
    expect(costBox().value).toBe("40");
  });

  it("will not convert until all three are filled", () => {
    // Applying half an answer writes a wrong quantity into stock.
    render(<Host />);
    openPicker();
    fireEvent.click(screen.getByText("Basmati Rice (5kg)"));
    fireEvent.click(screen.getByText(/It came in bags, boxes or cases/));
    fireEvent.change(screen.getByPlaceholderText("2"), { target: { value: "2" } });

    expect((screen.getByText("Use this") as HTMLButtonElement).disabled).toBe(true);
  });
});

describe("the rows themselves", () => {
  it("adds another row on request", () => {
    render(<Host />);
    fireEvent.click(screen.getByText(/Add another item/));
    expect(screen.getAllByPlaceholderText("Type an item name or SKU")).toHaveLength(2);
  });

  it("offers no remove button while one row is all there is", () => {
    // Removing the only line leaves a form that cannot be submitted and no
    // way back to one that can.
    render(<Host />);
    expect(screen.queryByLabelText("Remove item")).toBeNull();
  });

  it("removes a row once there is more than one", () => {
    render(<Host />);
    fireEvent.click(screen.getByText(/Add another item/));
    fireEvent.click(screen.getAllByLabelText("Remove item")[0]);
    expect(screen.getAllByPlaceholderText("Type an item name or SKU")).toHaveLength(1);
  });
});
