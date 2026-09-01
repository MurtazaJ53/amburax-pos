/** Entrance delays for a list, that stay sane when the list is long.
 *
 *  A staggered fade reads beautifully on eight rows and is a bug on two
 *  hundred. The animation is declared with `animation-fill-mode: both`, so
 *  every row sits at opacity 0 until its own delay elapses - the rows exist,
 *  they are simply invisible.
 *
 *  At 40ms a row, the dashboard's recent sales panel put row 20 at 1.0s and
 *  row 199 at 8.2s. A shopkeeper opening the dashboard and looking at it for
 *  a second sees exactly twenty sales and concludes the shop only records
 *  twenty. That is not a slow animation; it is a screen lying about how much
 *  data it has, which is the same failure as a list that silently pages
 *  short.
 *
 *  So the stagger is capped: the first few rows arrive in sequence, and
 *  everything after them arrives with the last of them. The effect is
 *  identical to the eye - nobody perceives the ninth row's individual timing -
 *  and the list is fully readable in well under a second however long it is.
 *
 *  One function rather than one expression per call site: the cap already
 *  existed in the stock table and had never been carried to the other three
 *  lists, which is exactly how the paging cursor went wrong.
 */

/** Rows after this one all share the same delay. */
const DEFAULT_CAP = 8;

/** Milliseconds between one row and the next. */
const DEFAULT_STEP = 40;

export type StaggerOptions = {
  /** Delay before the first row, for a list that follows other content in. */
  offset?: number;
  /** Milliseconds between consecutive rows. */
  step?: number;
  /** How many rows are staggered before the delay stops growing. */
  cap?: number;
};

/** A CSS `animation-delay` for row `index`, bounded however long the list is. */
export function staggerDelay(index: number, options: StaggerOptions = {}): string {
  const { offset = 0, step = DEFAULT_STEP, cap = DEFAULT_CAP } = options;
  const position = Math.max(0, Math.min(index, cap));
  return `${offset + position * step}ms`;
}

/** The longest any row can wait, for a test or a comment to point at. */
export function longestStagger(options: StaggerOptions = {}): number {
  const { offset = 0, step = DEFAULT_STEP, cap = DEFAULT_CAP } = options;
  return offset + cap * step;
}
