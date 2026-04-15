// Pure rating helpers shared between the RatingPicker client component
// and its vitest suite. Kept in plain TypeScript (no React imports) so
// vitest in the node environment can cover every branch without having
// to transpile JSX or mount the component — same discipline as
// lib/reviews.ts (Sprint 5 / S5-05).
//
// The component at components/rating-picker.tsx imports these helpers
// and layers useState + event handlers on top. If you change anything
// here, verify that rating-picker.tsx still type-checks against the
// new signatures.

export const DEFAULT_MAX_RATING = 5;

// The star value shown in the UI at any moment: when the user is
// hovering a star, that hover value takes precedence; otherwise the
// persisted rating is shown. Pure function of state + hover pair.
export function computeDisplay(rating: number, hover: number | null): number {
  return hover !== null ? hover : rating;
}

// Coerces arbitrary numeric input to a safe integer in [0, max].
// Used when seeding state from a potentially-untrusted defaultValue
// prop and when processing click events that could (in theory) fire
// with an out-of-range value. Non-finite inputs collapse to 0 rather
// than throwing — the picker must always have a valid state.
export function clampRating(
  value: number,
  max: number = DEFAULT_MAX_RATING,
): number {
  if (!Number.isFinite(value)) return 0;
  const rounded = Math.floor(value);
  if (rounded < 0) return 0;
  if (rounded > max) return max;
  return rounded;
}

// Returns the `max`-element array of filled/empty star characters the
// picker renders. Exported so the server-side render path (before the
// client component hydrates) has identical output to the hydrated
// path — no hydration mismatch warnings.
export function renderStars(
  displayValue: number,
  max: number = DEFAULT_MAX_RATING,
): readonly string[] {
  return Array.from({ length: max }, (_, i) =>
    i + 1 <= displayValue ? "★" : "☆",
  );
}

// Guards the final submission value before the client component
// hands it to the form action. Mirrors the REV-001 rule in
// lib/reviews.ts: integer in [1, max]. The server action revalidates
// the same rule — this client-side check exists to fail fast with a
// better UX (disabled submit button) before the network round-trip.
export function isValidSubmittedRating(
  value: unknown,
  max: number = DEFAULT_MAX_RATING,
): boolean {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= 1 &&
    value <= max
  );
}
