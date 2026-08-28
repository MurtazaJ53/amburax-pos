import { describe, expect, it } from "vitest";

import { ApiError } from "@/lib/admin-api";
import { describeLoadFailure } from "@/lib/load-failure";

/** Six screens told every failure the same story: the backend is unreachable,
 *  go and check the api container. For a cashier opening a screen their role
 *  does not include, every word of that is false — and it is the sentence
 *  that turns a working permission check into a phone call about an outage. */
describe("describeLoadFailure", () => {
  it("calls a refusal a refusal", () => {
    const failure = describeLoadFailure(new ApiError(403, "forbidden"), "your team");

    expect(failure.detail).toContain("Your role");
    expect(failure.detail).not.toContain("container");
  });

  it("says where a refusal can be undone", () => {
    // Otherwise the answer is "no" with nothing to do about it.
    const failure = describeLoadFailure(new ApiError(403, "forbidden"), "your team");

    expect(failure.detail).toContain("Team");
  });

  it("names what was refused, so the message fits the screen it is on", () => {
    const failure = describeLoadFailure(new ApiError(403, "forbidden"), "your products");

    expect(failure.detail).toContain("your products");
  });

  it("never shows a stack trace for a refusal", () => {
    // Nothing is broken, so there is nothing for anybody to read a log about.
    const failure = describeLoadFailure(new ApiError(403, "nope"), "your team");

    expect(failure.technical).toBeNull();
  });

  it("tells a signed-out visitor to sign in", () => {
    const failure = describeLoadFailure(new ApiError(401, "expired"), "your team");

    expect(failure.title.toLowerCase()).toContain("signed out");
    expect(failure.technical).toBeNull();
  });

  it("asks for a pause when the server is throttling", () => {
    const failure = describeLoadFailure(new ApiError(429, "slow down"), "your team");

    expect(failure.detail.toLowerCase()).toContain("wait");
    expect(failure.detail).not.toContain("container");
  });

  it("still points at the container when the server really did fail", () => {
    // The original message was not wrong, only wrongly applied. A 500 is
    // exactly the case it was written for, and it must survive.
    const failure = describeLoadFailure(new ApiError(500, "boom"), "your team");

    expect(failure.detail).toContain("container");
    expect(failure.technical).toBe("boom");
  });

  it("distinguishes a server that answered badly from one that never answered", () => {
    const upstream = describeLoadFailure(new ApiError(500, "boom"), "your team");
    const offline = describeLoadFailure(new TypeError("fetch failed"), "your team");

    expect(offline.title).not.toBe(upstream.title);
    expect(offline.detail).toContain("could not contact");
  });

  it("keeps the underlying message when somebody has to go and read a log", () => {
    const failure = describeLoadFailure(new TypeError("ECONNREFUSED"), "your team");

    expect(failure.technical).toBe("ECONNREFUSED");
  });

  it("survives being handed something that is not an Error at all", () => {
    const failure = describeLoadFailure("just a string", "your team");

    expect(failure.title).toBeTruthy();
    expect(failure.detail).toContain("your team");
  });
});
