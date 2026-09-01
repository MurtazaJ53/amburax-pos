import { describe, expect, it } from "vitest";

import { longestStagger, staggerDelay } from "./stagger";

/** The dashboard's recent sales panel appeared to hold only twenty sales.
 *
 *  It held two hundred. Each row carried `animationDelay: 240 + index * 40`
 *  against an animation declared with fill-mode `both`, so every row waited at
 *  opacity 0 for its own delay. One second after the page painted, the rows
 *  that had arrived were those where 240 + index x 40 <= 1000 - index 0 to 19.
 *  Exactly twenty. The rest were present, styled, and invisible, the last of
 *  them for over eight seconds.
 *
 *  These tests are about the shape of the function rather than any one number:
 *  whatever the step and offset, a list must be fully visible quickly, and it
 *  must not get slower as the shop gets bigger.
 */
describe("staggered list entrances", () => {
  const ms = (value: string) => Number(value.replace("ms", ""));

  it("still staggers the first few rows", () => {
    // The effect has to survive the fix, or this is just deleting the design.
    expect(ms(staggerDelay(0))).toBeLessThan(ms(staggerDelay(1)));
    expect(ms(staggerDelay(1))).toBeLessThan(ms(staggerDelay(2)));
  });

  it("stops growing once the stagger has been seen", () => {
    // Nobody perceives the ninth row's individual timing.
    expect(staggerDelay(40)).toBe(staggerDelay(200));
  });

  it("never makes a row wait longer than the cap, however long the list", () => {
    for (const index of [20, 199, 5_000, 19_543]) {
      expect(ms(staggerDelay(index))).toBeLessThanOrEqual(longestStagger());
    }
  });

  it("shows a long list inside a second", () => {
    // The actual complaint. 19,543 sales is a real shop's history.
    expect(ms(staggerDelay(19_543, { offset: 240 }))).toBeLessThan(1000);
  });

  it("would have failed on the delay that caused this", () => {
    // The old expression, kept here so the regression is named rather than
    // merely prevented.
    const old = (index: number) => 240 + index * 40;

    expect(old(199)).toBeGreaterThan(8000);
    expect(ms(staggerDelay(199, { offset: 240 }))).toBeLessThan(1000);
  });

  it("honours an offset for a list that follows other content in", () => {
    expect(ms(staggerDelay(0, { offset: 200 }))).toBe(200);
  });

  it("honours a custom step", () => {
    expect(ms(staggerDelay(1, { step: 25 }))).toBe(25);
  });

  it("treats a negative index as the first row rather than a negative delay", () => {
    // A negative animation-delay starts the animation part-way through, which
    // would make one row appear without its entrance.
    expect(ms(staggerDelay(-5))).toBe(0);
  });
});
