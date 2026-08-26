/**
 * @vitest-environment happy-dom
 *
 * The hook that decides whether a saved change appears on screen.
 *
 * Both rules here fail silently. A refresh that never fires looks exactly
 * like a save that did not work, and an unstable identity looks like nothing
 * at all until a screen quietly re-runs an effect on every render.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render } from "@testing-library/react";

import { useServerRefresh } from "./use-server-refresh";

const refresh = vi.fn();

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh }),
}));

beforeEach(() => refresh.mockClear());
// Explicit: this project does not run vitest with globals, so the automatic
// cleanup React Testing Library normally installs never registers.
afterEach(cleanup);

/** Hands the hook's result back so a test can call it and compare it. */
function Probe({ onRender }: { onRender: (refreshServerData: () => void) => void }) {
  onRender(useServerRefresh());
  return null;
}

describe("useServerRefresh", () => {
  it("does not refresh until it is called", () => {
    // Refreshing on mount would put a second server round-trip on every
    // screen that loads, for no change.
    render(<Probe onRender={() => {}} />);
    expect(refresh).not.toHaveBeenCalled();
  });

  it("re-runs the page's server data when called", () => {
    let refreshServerData: (() => void) | null = null;
    render(<Probe onRender={(fn) => { refreshServerData = fn; }} />);

    refreshServerData!();

    expect(refresh).toHaveBeenCalledTimes(1);
  });

  it("keeps the same identity across renders", () => {
    // It is passed into dependency arrays - data-health lists it in a
    // useCallback. A new function every render would rebuild that callback
    // every render, and anything keyed on it would re-run without end.
    const seen: Array<() => void> = [];
    const { rerender } = render(<Probe onRender={(fn) => seen.push(fn)} />);
    rerender(<Probe onRender={(fn) => seen.push(fn)} />);

    expect(seen.length).toBeGreaterThan(1);
    expect(new Set(seen).size).toBe(1);
  });

  it("can be called more than once", () => {
    // Several writes in a row - saving three rows of a form - must each bring
    // the page up to date, rather than only the first.
    let refreshServerData: (() => void) | null = null;
    render(<Probe onRender={(fn) => { refreshServerData = fn; }} />);

    refreshServerData!();
    refreshServerData!();
    refreshServerData!();

    expect(refresh).toHaveBeenCalledTimes(3);
  });
});
