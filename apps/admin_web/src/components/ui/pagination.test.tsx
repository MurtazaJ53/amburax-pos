import { describe, expect, it } from "vitest";

import { pagesToShow } from "./pagination";

/** Which page numbers to draw.
 *
 *  On nineteen thousand bills at fifty a page there are nearly four hundred
 *  pages. Drawing them all is unreadable and unclickable, so the row is a
 *  window - and a window that lies about which pages exist is worse than a
 *  "load older" button, because somebody clicks 4 expecting what follows 3.
 */
describe("the page numbers shown", () => {
  it("shows every page when there are few", () => {
    expect(pagesToShow(1, 5)).toEqual([1, 2, 3, 4, 5]);
  });

  it("shows one page as itself", () => {
    expect(pagesToShow(1, 1)).toEqual([1]);
  });

  it("keeps the first and last reachable in one click", () => {
    const shown = pagesToShow(50, 400);
    expect(shown[0]).toBe(1);
    expect(shown[shown.length - 1]).toBe(400);
  });

  it("always includes the page you are on", () => {
    for (const page of [1, 2, 7, 199, 400]) {
      expect(pagesToShow(page, 400)).toContain(page);
    }
  });

  it("puts a gap only where pages are actually missing", () => {
    // "1 … 2" would be a lie told to save one character.
    const shown = pagesToShow(3, 400);
    const numbers = shown.filter((entry) => entry !== "gap") as number[];
    for (let i = 1; i < numbers.length; i++) {
      const contiguous = numbers[i] - numbers[i - 1] === 1;
      const gapBetween = shown.indexOf(numbers[i]) - shown.indexOf(numbers[i - 1]) > 1;
      expect(contiguous || gapBetween).toBe(true);
    }
  });

  it("never repeats a page", () => {
    for (const page of [1, 2, 3, 200, 398, 399, 400]) {
      const numbers = pagesToShow(page, 400).filter((e) => e !== "gap");
      expect(new Set(numbers).size).toBe(numbers.length);
    }
  });

  it("stays a manageable width however deep the list", () => {
    // The whole reason for a window. Ten thousand pages must not draw ten
    // thousand buttons.
    expect(pagesToShow(5000, 10000).length).toBeLessThanOrEqual(9);
  });

  it("reads in ascending order", () => {
    const numbers = pagesToShow(200, 400).filter((e) => e !== "gap") as number[];
    expect(numbers).toEqual([...numbers].sort((a, b) => a - b));
  });

  it("does not draw a leading gap at the start of the list", () => {
    expect(pagesToShow(1, 400)[0]).toBe(1);
    expect(pagesToShow(2, 400)[1]).toBe(2);
  });

  it("does not draw a trailing gap at the end of the list", () => {
    const shown = pagesToShow(400, 400);
    expect(shown[shown.length - 1]).toBe(400);
    expect(shown[shown.length - 2]).toBe(399);
  });
});
