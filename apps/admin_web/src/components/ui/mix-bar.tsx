/**
 * A one-line breakdown of a total into its parts — payment modes today,
 * expenses by category, stock by supplier. Segments carry a legend with the
 * real amounts, because a bar alone cannot be read to the rupee.
 */

export type MixSegment = {
  key: string;
  label: string;
  amount: number;
  /** Any CSS colour; callers pass design tokens. */
  color: string;
};

type MixBarProps = {
  segments: MixSegment[];
  format: (amount: number) => string;
  ariaLabel: string;
};

export function MixBar({ segments, format, ariaLabel }: MixBarProps) {
  const total = segments.reduce((sum, segment) => sum + segment.amount, 0);

  if (total <= 0) {
    return null;
  }

  return (
    <div>
      <div className="mb-2.5 flex h-2 gap-0.5" role="img" aria-label={ariaLabel}>
        {segments.map((segment) => (
          <span
            key={segment.key}
            className="block rounded-full"
            style={{ flex: segment.amount, background: segment.color }}
          />
        ))}
      </div>
      <ul className="flex list-none flex-wrap gap-x-4 gap-y-1.5 p-0 m-0">
        {segments.map((segment) => (
          <li
            key={segment.key}
            className="flex items-center gap-1.5 text-[11.5px] font-semibold text-[var(--text-secondary)]"
          >
            <span
              className="block h-2 w-2 flex-none rounded-[3px]"
              style={{ background: segment.color }}
              aria-hidden="true"
            />
            {segment.label}{" "}
            <b className="tnum font-mono font-semibold text-[var(--text-primary)]">
              {format(segment.amount)}
            </b>
          </li>
        ))}
      </ul>
    </div>
  );
}
