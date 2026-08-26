import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { toRowError, type RowError } from "@/lib/import-rows";

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

const API_BASE_URL = process.env.BUSINESS_HUB_API_BASE_URL || "http://127.0.0.1:8000/api/v1";

/** The backend caps a batch at 1000 rows, so send in chunks under that. */
const CHUNK_SIZE = 500;

/** Enough to act on; the true total travels as `errorCount`. */
const MAX_SHOWN_ERRORS = 50;



const TARGETS = {
  products: { path: "inventory/bulk/", key: "items" },
  customers: { path: "customers/bulk/", key: "customers" },
} as const;

export async function POST(req: NextRequest) {
  try {
    const cookieStore = await cookies();
    const token = cookieStore.get("bh_access_token")?.value;
    const shopId = cookieStore.get("bh_active_shop")?.value;
    if (!token || !shopId) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = await req.json();
    const kind = body?.kind as keyof typeof TARGETS;
    const rows = body?.rows;
    const filename = typeof body?.filename === "string" ? body.filename : "";
    const target = TARGETS[kind];

    if (!target) {
      return NextResponse.json({ error: `Unknown import kind: ${kind}` }, { status: 400 });
    }
    if (!Array.isArray(rows) || rows.length === 0) {
      return NextResponse.json({ error: "Nothing to import." }, { status: 400 });
    }

    let created = 0;
    let updated = 0;
    let skipped = 0;
    let errorCount = 0;
    const errors: RowError[] = [];

    // Sequential, not parallel: the backend matches each row against existing
    // items to avoid creating duplicates, and concurrent batches could both
    // miss the same match and create two copies.
    for (let start = 0; start < rows.length; start += CHUNK_SIZE) {
      const chunk = rows.slice(start, start + CHUNK_SIZE);
      const res = await fetch(`${API_BASE_URL}/shops/${shopId}/${target.path}`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          Accept: "application/json",
        },
        // Forwarded so each batch is recognisable as having come from this
        // file. Note that a file over CHUNK_SIZE rows becomes several
        // batches, and each is undone separately - the filename is what ties
        // them together on screen.
        body: JSON.stringify({ [target.key]: chunk, filename }),
      });

      const text = await res.text();
      if (!res.ok) {
        // Report what already landed rather than implying nothing happened.
        return NextResponse.json(
          {
            error: `Import stopped after ${created + updated} row(s): ${text}`,
            created,
            updated,
            skipped,
            errors,
            errorCount,
          },
          { status: res.status }
        );
      }

      const result = JSON.parse(text);
      created += result.created ?? 0;
      updated += result.updated ?? 0;
      skipped += result.skipped ?? 0;
      errorCount += result.error_count ?? result.skipped ?? 0;

      // The backend numbers rejected rows within ITS request, so every chunk
      // restarts at zero. Without adding the chunk offset, a 2,000-row import
      // reports four different failures all as "row 5" and none of them can be
      // found in the spreadsheet. Converted to a 1-based row number including
      // the header, so it matches what the person sees in Excel.
      if (Array.isArray(result.errors)) {
        for (const raw of result.errors) errors.push(toRowError(start, raw));
      }
    }

    return NextResponse.json({
      created,
      updated,
      skipped,
      errors: errors.slice(0, MAX_SHOWN_ERRORS),
      errorCount,
    });
  } catch (error) {
    return NextResponse.json(
      { error: errorMessage(error, "Internal server error") },
      { status: 500 }
    );
  }
}
