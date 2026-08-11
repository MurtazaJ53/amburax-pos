/**
 * Turning a backend row index into the row number a person can find.
 *
 * Extracted so it can be tested. The bug it exists to prevent shipped once and
 * was invisible: the backend numbers rejected rows within ITS request, and the
 * proxy sends the file in chunks of 500, so every chunk restarted at zero. A
 * 2,000-row import reported four separate failures all as "row 5", and none of
 * them could be found in the spreadsheet.
 */

/** A rejected row, described so it can be found in the original spreadsheet. */
export type RowError = {
  /** 1-based row number as it appears in Excel, header included. */
  row: number;
  name: string;
  sku: string;
  message: string;
};

/**
 * @param chunkStart index of the first data row in this chunk
 * @param index      the backend's index within that chunk
 *
 * The `+ 2` converts a 0-based data index into what a spreadsheet shows: one
 * for the header row, one because spreadsheets count from 1. Data row 0 is
 * row 2 on screen.
 */
export function spreadsheetRow(chunkStart: number, index: number): number {
  return chunkStart + index + 2;
}

/** Normalise one backend error into a row a person can act on. */
export function toRowError(chunkStart: number, raw: unknown): RowError {
  const r = (raw ?? {}) as Record<string, unknown>;
  return {
    row: spreadsheetRow(chunkStart, Number(r.index ?? 0)),
    name: String(r.name ?? ""),
    sku: String(r.sku ?? ""),
    message: String(r.message ?? "Could not be read."),
  };
}
