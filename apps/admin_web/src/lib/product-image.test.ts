import { describe, expect, it } from "vitest";

import {
  dataUriBytes,
  fitWithin,
  formatBytes,
  isAcceptedType,
  MAX_BYTES,
  MAX_EDGE,
} from "./product-image";

describe("scaling a photo down to fit a tile", () => {
  it("shrinks a big landscape photo by its longest edge", () => {
    expect(fitWithin({ width: 4000, height: 3000 }, 400)).toEqual({
      width: 400,
      height: 300,
    });
  });

  it("shrinks a portrait photo the same way", () => {
    expect(fitWithin({ width: 3000, height: 4000 }, 400)).toEqual({
      width: 300,
      height: 400,
    });
  });

  it("leaves a small picture alone rather than upscaling it", () => {
    // Blowing up a 120px thumbnail invents pixels and makes the stored
    // string bigger for a worse-looking tile.
    expect(fitWithin({ width: 120, height: 90 }, 400)).toEqual({
      width: 120,
      height: 90,
    });
  });

  it("keeps a square square", () => {
    expect(fitWithin({ width: 2000, height: 2000 }, 400)).toEqual({
      width: 400,
      height: 400,
    });
  });

  it("never rounds a very wide banner down to zero height", () => {
    const fitted = fitWithin({ width: 4000, height: 3 }, 400);
    expect(fitted.width).toBe(400);
    expect(fitted.height).toBeGreaterThanOrEqual(1);
  });

  it("returns nothing for a zero-sized image instead of dividing by zero", () => {
    expect(fitWithin({ width: 0, height: 0 }, 400)).toEqual({ width: 0, height: 0 });
  });

  it("defaults to the 400px cap the tiles are drawn at", () => {
    expect(fitWithin({ width: 1000, height: 1000 })).toEqual({
      width: MAX_EDGE,
      height: MAX_EDGE,
    });
  });
});

describe("measuring what a data URI really costs", () => {
  // Every inventory response carries this string, to every client, so the
  // size has to be measured rather than hoped about.
  it("counts three bytes for every four base64 characters", () => {
    // "AAAA" is 4 characters with no padding: 3 bytes.
    expect(dataUriBytes("data:image/jpeg;base64,AAAA")).toBe(3);
  });

  it("discounts one padding character", () => {
    expect(dataUriBytes("data:image/jpeg;base64,AAA=")).toBe(2);
  });

  it("discounts two padding characters", () => {
    expect(dataUriBytes("data:image/jpeg;base64,AA==")).toBe(1);
  });

  it("reports zero for something that is not a data URI", () => {
    expect(dataUriBytes("https://example.com/cat.jpg")).toBe(0);
  });

  it("reads an empty payload as zero", () => {
    expect(dataUriBytes("data:image/jpeg;base64,")).toBe(0);
  });

  it("keeps the cap well under a hundred kilobytes", () => {
    // Four hundred items at this size is roughly 24MB of JSON, which is
    // already the reason the cap exists.
    expect(MAX_BYTES).toBeLessThanOrEqual(60_000);
  });
});

describe("which files are allowed in", () => {
  it("takes the formats a phone camera produces", () => {
    expect(isAcceptedType("image/jpeg")).toBe(true);
    expect(isAcceptedType("image/png")).toBe(true);
    expect(isAcceptedType("image/webp")).toBe(true);
  });

  it("ignores case, because browsers are inconsistent about it", () => {
    expect(isAcceptedType("IMAGE/JPEG")).toBe(true);
  });

  it("refuses a PDF or a HEIC that canvas cannot draw", () => {
    expect(isAcceptedType("application/pdf")).toBe(false);
    expect(isAcceptedType("image/heic")).toBe(false);
  });
});

describe("telling a shopkeeper how big something is", () => {
  it("uses bytes, kilobytes and megabytes as they arrive", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(2048)).toBe("2 KB");
    expect(formatBytes(3_145_728)).toBe("3.0 MB");
  });
});
