import { describe, expect, it } from "vitest";

import { clampPage, pageCount, paginate } from "./paging";

const items = Array.from({ length: 14 }, (_, i) => i + 1);

describe("pageCount", () => {
  it("counts a part-full last page", () => {
    expect(pageCount(14, 6)).toBe(3);
  });

  it("is zero for an empty list, not one empty page", () => {
    expect(pageCount(0, 6)).toBe(0);
  });

  it("is zero rather than dividing by zero", () => {
    expect(pageCount(10, 0)).toBe(0);
  });
});

describe("clampPage", () => {
  it("keeps an in-range index", () => {
    expect(clampPage(1, 3)).toBe(1);
  });

  it("pulls a stale index back rather than blanking the list", () => {
    // The list can shrink under a held page index when stock is refilled.
    expect(clampPage(5, 3)).toBe(2);
    expect(clampPage(-2, 3)).toBe(0);
  });

  it("survives nonsense", () => {
    expect(clampPage(Number.NaN, 3)).toBe(0);
    expect(clampPage(0, 0)).toBe(0);
  });
});

describe("paginate", () => {
  it("returns the first page and knows there is more", () => {
    const page = paginate(items, 0, 6);
    expect(page.items).toEqual([1, 2, 3, 4, 5, 6]);
    expect(page.current).toBe(1);
    expect(page.total).toBe(3);
    expect(page.hasPrevious).toBe(false);
    expect(page.hasNext).toBe(true);
  });

  it("returns a part-full last page and stops there", () => {
    const page = paginate(items, 2, 6);
    expect(page.items).toEqual([13, 14]);
    expect(page.hasNext).toBe(false);
    expect(page.hasPrevious).toBe(true);
  });

  it("reports the range it is showing, for a truthful caption", () => {
    const page = paginate(items, 1, 6);
    expect(page.firstIndex).toBe(7);
    expect(page.lastIndex).toBe(12);
  });

  it("clamps an index past the end instead of showing nothing", () => {
    expect(paginate(items, 99, 6).items).toEqual([13, 14]);
  });

  it("handles a list shorter than one page", () => {
    const page = paginate([1, 2], 0, 6);
    expect(page.total).toBe(1);
    expect(page.hasNext).toBe(false);
    expect(page.lastIndex).toBe(2);
  });

  it("handles an empty list without claiming a page", () => {
    const page = paginate([], 0, 6);
    expect(page.items).toEqual([]);
    expect(page.current).toBe(0);
    expect(page.total).toBe(0);
    expect(page.firstIndex).toBe(0);
  });

  it("tolerates a non-array, which a failed fetch can produce", () => {
    expect(paginate(null as unknown as number[], 0, 6).items).toEqual([]);
  });
});
