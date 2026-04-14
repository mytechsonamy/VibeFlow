// Review validation + persistence for the Next.js demo.
//
// Pure functions — no React, no Next. Every requirement in PRD §3.2
// (REV-*) is covered by tests in tests/reviews.test.ts.
// The server action at actions/submit-review.ts wraps these functions.

export interface Review {
  readonly id: string;
  readonly productId: string;
  readonly rating: number;
  readonly text: string;
  readonly createdAt: string; // ISO-8601
}

export interface ValidateReviewInput {
  readonly rating: unknown;
  readonly text: unknown;
}

export type ValidateReviewResult =
  | { readonly ok: true; readonly rating: number; readonly text: string }
  | { readonly ok: false; readonly error: string };

const MIN_TEXT_LENGTH = 10;
const MAX_TEXT_LENGTH = 500;

// REV-003 — configured profanity list (sample; intentionally small).
// Exported so tests can reach it without guessing internals.
export const FORBIDDEN_WORDS: readonly string[] = Object.freeze([
  "badword1",
  "badword2",
  "forbidden",
]);

// REV-001 + REV-002 + REV-003 — returns a discriminated result instead
// of throwing so the server action can map it straight to its return
// type without a try/catch.
export function validateReview(input: ValidateReviewInput): ValidateReviewResult {
  const { rating, text } = input;

  if (typeof rating !== "number" || !Number.isInteger(rating) || rating < 1 || rating > 5) {
    return { ok: false, error: "rating must be integer 1-5" };
  }

  if (typeof text !== "string") {
    return { ok: false, error: "text must be a string" };
  }

  const trimmed = text.trim();
  if (trimmed.length < MIN_TEXT_LENGTH) {
    return { ok: false, error: "text too short" };
  }
  if (trimmed.length > MAX_TEXT_LENGTH) {
    return { ok: false, error: "text too long" };
  }

  const lower = trimmed.toLowerCase();
  for (const forbidden of FORBIDDEN_WORDS) {
    if (lower.includes(forbidden)) {
      return { ok: false, error: "text contains forbidden words" };
    }
  }

  return { ok: true, rating, text: trimmed };
}

// In-memory review store. Scoped to the module so tests can reset it
// between runs without reaching into globals.
const STORE = new Map<string, Review>();
let SEQ = 0;

// REV-004 — id format `rev-<productId>-<n>`, monotonic within a run.
export function persistReview(input: {
  readonly productId: string;
  readonly rating: number;
  readonly text: string;
  readonly now?: Date;
}): Review {
  SEQ += 1;
  const review: Review = {
    id: `rev-${input.productId}-${SEQ}`,
    productId: input.productId,
    rating: input.rating,
    text: input.text,
    createdAt: (input.now ?? new Date()).toISOString(),
  };
  STORE.set(review.id, review);
  return review;
}

export function getReview(id: string): Review | undefined {
  return STORE.get(id);
}

export function __resetReviewsForTests(): void {
  STORE.clear();
  SEQ = 0;
}
