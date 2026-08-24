/**
 * A takings curve, drawn small.
 *
 * Deliberately not a charting library: this renders on the server as plain
 * SVG, so it costs no client JavaScript and cannot shift layout. Reusable by
 * any screen that wants a trend beside a figure.
 */

export type SparklinePoint = {
  label: string;
  amount: number;
};

type SparklineProps = {
  points: SparklinePoint[];
  /** Sentence describing the shape, for screen readers. */
  ariaLabel: string;
  height?: number;
  /** Drop the entry animation where motion would be noise. */
  animate?: boolean;
};

const WIDTH = 520;
const PAD_TOP = 8;
const PAD_BOTTOM = 8;

export function Sparkline({
  points,
  ariaLabel,
  height = 74,
  animate = true,
}: SparklineProps) {
  if (points.length === 0) {
    return null;
  }

  const usable = height - PAD_TOP - PAD_BOTTOM;
  const peak = Math.max(...points.map((point) => point.amount), 0);

  // A single reading has no line to draw, so hold it at mid-height rather
  // than dividing by zero.
  const step = points.length > 1 ? WIDTH / (points.length - 1) : 0;

  const coords = points.map((point, index) => {
    const x = points.length > 1 ? index * step : WIDTH / 2;
    const ratio = peak > 0 ? point.amount / peak : 0;
    const y = PAD_TOP + usable - ratio * usable;
    return { x, y };
  });

  const line = coords
    .map((coord, index) => `${index === 0 ? "M" : "L"}${coord.x.toFixed(1)},${coord.y.toFixed(1)}`)
    .join(" ");

  const area = `${line} L${WIDTH},${height} L0,${height} Z`;

  // Rough path length, so the draw animation completes rather than snapping.
  const length = Math.ceil(
    coords.reduce((total, coord, index) => {
      if (index === 0) return 0;
      const previous = coords[index - 1];
      return total + Math.hypot(coord.x - previous.x, coord.y - previous.y);
    }, 0) + 40,
  );

  const last = coords[coords.length - 1];
  const gradientId = `spark-${points.length}-${Math.round(peak)}`;

  return (
    <svg
      viewBox={`0 0 ${WIDTH} ${height}`}
      preserveAspectRatio="none"
      role="img"
      aria-label={ariaLabel}
      className="block w-full"
      style={{ height }}
    >
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="var(--primary-bright)" stopOpacity="0.28" />
          <stop offset="100%" stopColor="var(--primary-bright)" stopOpacity="0" />
        </linearGradient>
      </defs>

      {/* Two faint rules give the curve something to be read against. */}
      <line
        x1="0"
        y1={PAD_TOP + usable * 0.33}
        x2={WIDTH}
        y2={PAD_TOP + usable * 0.33}
        stroke="var(--border-soft)"
        strokeWidth="1"
        strokeDasharray="3 5"
      />
      <line
        x1="0"
        y1={PAD_TOP + usable * 0.66}
        x2={WIDTH}
        y2={PAD_TOP + usable * 0.66}
        stroke="var(--border-soft)"
        strokeWidth="1"
        strokeDasharray="3 5"
      />

      <path d={area} fill={`url(#${gradientId})`} className={animate ? "spark-area" : undefined} />
      <path
        d={line}
        fill="none"
        stroke="var(--primary-bright)"
        strokeWidth="2.4"
        strokeLinecap="round"
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
        className={animate ? "spark-line" : undefined}
        style={animate ? ({ "--spark-length": length } as React.CSSProperties) : undefined}
      />
      <circle
        cx={Math.min(last.x, WIDTH - 4)}
        cy={last.y}
        r="4.5"
        fill="var(--surface)"
        stroke="var(--primary-bright)"
        strokeWidth="2.6"
        className={animate ? "spark-dot" : undefined}
      />
    </svg>
  );
}
