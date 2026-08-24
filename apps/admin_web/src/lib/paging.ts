/** Paging a short preview list.
 *
 *  The low-stock panel showed six items under a badge reading 135, with no
 *  way to reach the seventh. This is the arithmetic behind a next/previous
 *  pair, kept here so the edges - a part-full last page, a list shorter than
 *  one page, an empty one - are pinned by tests rather than discovered on a
 *  screen at the counter.
 */

export type Page<T> = {
  items: T[];
  /** 1-based, for display. */
  current: number;
  total: number;
  hasPrevious: boolean;
  hasNext: boolean;
  /** Index of the first item on this page, 1-based. */
  firstIndex: number;
  /** Index of the last item on this page, 1-based. */
  lastIndex: number;
};

/** Clamp a page index into range, so a stale index can never blank the list. */
export function clampPage(index: number, total: number): number {
  if (!Number.isFinite(index) || total <= 0) return 0;
  return Math.max(0, Math.min(Math.floor(index), total - 1));
}

export function pageCount(length: number, size: number): number {
  if (size <= 0 || length <= 0) return 0;
  return Math.ceil(length / size);
}

/** Slice `items` into the page at `index`, tolerating an out-of-range index. */
export function paginate<T>(items: T[], index: number, size: number): Page<T> {
  const list = Array.isArray(items) ? items : [];
  const total = pageCount(list.length, size);
  const safe = clampPage(index, total);
  const start = safe * size;
  const slice = list.slice(start, start + size);

  return {
    items: slice,
    current: total === 0 ? 0 : safe + 1,
    total,
    hasPrevious: safe > 0,
    hasNext: safe + 1 < total,
    firstIndex: slice.length === 0 ? 0 : start + 1,
    lastIndex: start + slice.length,
  };
}
