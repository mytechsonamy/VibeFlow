import { describe, it, expect, beforeEach } from "vitest";
import {
  validateReview,
  persistReview,
  getReview,
  __resetReviewsForTests,
  FORBIDDEN_WORDS,
} from "../lib/reviews";

beforeEach(() => {
  __resetReviewsForTests();
});

describe("validateReview — REV-001 rating bounds", () => {
  it("accepts rating 1", () => {
    const r = validateReview({ rating: 1, text: "solid purchase overall" });
    expect(r.ok).toBe(true);
  });

  it("accepts rating 5", () => {
    const r = validateReview({ rating: 5, text: "solid purchase overall" });
    expect(r.ok).toBe(true);
  });

  it("rejects rating 0", () => {
    const r = validateReview({ rating: 0, text: "solid purchase overall" });
    expect(r).toEqual({ ok: false, error: "rating must be integer 1-5" });
  });

  it("rejects rating 6", () => {
    const r = validateReview({ rating: 6, text: "solid purchase overall" });
    expect(r).toEqual({ ok: false, error: "rating must be integer 1-5" });
  });

  it("rejects non-integer rating 4.5", () => {
    const r = validateReview({ rating: 4.5, text: "solid purchase overall" });
    expect(r).toEqual({ ok: false, error: "rating must be integer 1-5" });
  });

  it("rejects non-numeric rating", () => {
    const r = validateReview({ rating: "5" as unknown, text: "solid purchase overall" });
    expect(r).toEqual({ ok: false, error: "rating must be integer 1-5" });
  });
});

describe("validateReview — REV-002 text length", () => {
  it("rejects text that is empty", () => {
    const r = validateReview({ rating: 3, text: "" });
    expect(r).toEqual({ ok: false, error: "text too short" });
  });

  it("rejects text shorter than 10 chars after trim", () => {
    const r = validateReview({ rating: 3, text: "   short   " });
    expect(r).toEqual({ ok: false, error: "text too short" });
  });

  it("accepts exactly 10 chars", () => {
    const r = validateReview({ rating: 3, text: "1234567890" });
    expect(r.ok).toBe(true);
  });

  it("rejects text longer than 500 chars", () => {
    const r = validateReview({ rating: 3, text: "x".repeat(501) });
    expect(r).toEqual({ ok: false, error: "text too long" });
  });

  it("accepts exactly 500 chars", () => {
    const r = validateReview({ rating: 3, text: "y".repeat(500) });
    expect(r.ok).toBe(true);
  });

  it("rejects non-string text", () => {
    const r = validateReview({ rating: 3, text: 42 as unknown });
    expect(r).toEqual({ ok: false, error: "text must be a string" });
  });
});

describe("validateReview — REV-003 profanity filter", () => {
  it("rejects a profane word regardless of case", () => {
    const r = validateReview({ rating: 3, text: "this is FORBIDDEN content indeed" });
    expect(r).toEqual({ ok: false, error: "text contains forbidden words" });
  });

  it("rejects a word embedded in a larger token", () => {
    const r = validateReview({
      rating: 3,
      text: `review prefixbadword1suffix here ok`,
    });
    expect(r).toEqual({ ok: false, error: "text contains forbidden words" });
  });

  it("exposes the profanity list for the demo to inspect", () => {
    expect(FORBIDDEN_WORDS.length).toBeGreaterThan(0);
  });
});

describe("validateReview — REV-003 INV-REV-TEXT-TRIMMED", () => {
  it("returned text has no leading/trailing whitespace", () => {
    const r = validateReview({ rating: 3, text: "   well worth the price   " });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.text).toBe("well worth the price");
    }
  });
});

describe("persistReview — REV-004 id format + monotonic ids (INV-REV-ID-STABLE)", () => {
  it("assigns `rev-<productId>-<n>` ids that increment across calls", () => {
    const a = persistReview({ productId: "p-headphones", rating: 5, text: "great battery life" });
    const b = persistReview({ productId: "p-headphones", rating: 4, text: "comfortable over long calls" });
    expect(a.id).toBe("rev-p-headphones-1");
    expect(b.id).toBe("rev-p-headphones-2");
  });

  it("round-trips a review through the in-memory store", () => {
    const review = persistReview({
      productId: "p-backpack",
      rating: 4,
      text: "good sized laptop sleeve",
      now: new Date("2026-04-14T10:00:00Z"),
    });
    const fetched = getReview(review.id);
    expect(fetched).toEqual(review);
    expect(fetched?.createdAt).toBe("2026-04-14T10:00:00.000Z");
  });
});
