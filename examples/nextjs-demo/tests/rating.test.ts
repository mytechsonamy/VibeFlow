import { describe, it, expect } from "vitest";
import {
  DEFAULT_MAX_RATING,
  clampRating,
  computeDisplay,
  renderStars,
  isValidSubmittedRating,
} from "../lib/rating";

describe("computeDisplay — hover takes precedence over rating", () => {
  it("returns the rating when hover is null", () => {
    expect(computeDisplay(3, null)).toBe(3);
  });

  it("returns the hover value when hovering", () => {
    expect(computeDisplay(3, 5)).toBe(5);
  });

  it("returns 0 when both rating and hover are 0/null", () => {
    expect(computeDisplay(0, null)).toBe(0);
  });

  it("returns the hover value even when rating is 0", () => {
    expect(computeDisplay(0, 4)).toBe(4);
  });

  it("lets the user hover over 0 to clear the preview (hover=0 vs null)", () => {
    // 0 is a valid hover value (explicit "no rating" preview) and
    // must NOT be treated as "null/not hovering".
    expect(computeDisplay(4, 0)).toBe(0);
  });
});

describe("clampRating — safe coercion into [0, max]", () => {
  it("clamps a negative value to 0", () => {
    expect(clampRating(-3)).toBe(0);
  });

  it("clamps a value beyond max down to max", () => {
    expect(clampRating(10, 5)).toBe(5);
  });

  it("rounds fractional values down", () => {
    expect(clampRating(4.9)).toBe(4);
    expect(clampRating(4.1)).toBe(4);
  });

  it("returns 0 for NaN", () => {
    expect(clampRating(Number.NaN)).toBe(0);
  });

  it("returns 0 for +Infinity", () => {
    expect(clampRating(Number.POSITIVE_INFINITY)).toBe(0);
  });

  it("returns 0 for -Infinity", () => {
    expect(clampRating(Number.NEGATIVE_INFINITY)).toBe(0);
  });

  it("accepts the exact min boundary (0)", () => {
    expect(clampRating(0)).toBe(0);
  });

  it("accepts the exact max boundary (DEFAULT_MAX_RATING)", () => {
    expect(clampRating(DEFAULT_MAX_RATING)).toBe(DEFAULT_MAX_RATING);
  });

  it("respects a custom max override", () => {
    expect(clampRating(8, 10)).toBe(8);
    expect(clampRating(11, 10)).toBe(10);
  });
});

describe("renderStars — server/client hydration parity", () => {
  it("returns all empty stars when displayValue is 0", () => {
    expect(renderStars(0, 5)).toEqual(["☆", "☆", "☆", "☆", "☆"]);
  });

  it("returns all filled stars when displayValue equals max", () => {
    expect(renderStars(5, 5)).toEqual(["★", "★", "★", "★", "★"]);
  });

  it("returns mixed stars for a mid value", () => {
    expect(renderStars(3, 5)).toEqual(["★", "★", "★", "☆", "☆"]);
  });

  it("uses DEFAULT_MAX_RATING when max is omitted", () => {
    expect(renderStars(2)).toHaveLength(DEFAULT_MAX_RATING);
  });

  it("returns an empty array when max is 0", () => {
    expect(renderStars(0, 0)).toEqual([]);
  });
});

describe("isValidSubmittedRating — mirrors REV-001 rule", () => {
  it("accepts every integer in [1, DEFAULT_MAX_RATING]", () => {
    for (let i = 1; i <= DEFAULT_MAX_RATING; i++) {
      expect(isValidSubmittedRating(i)).toBe(true);
    }
  });

  it("rejects 0 (no rating submitted)", () => {
    expect(isValidSubmittedRating(0)).toBe(false);
  });

  it("rejects max+1", () => {
    expect(isValidSubmittedRating(DEFAULT_MAX_RATING + 1)).toBe(false);
  });

  it("rejects non-integer numbers", () => {
    expect(isValidSubmittedRating(3.5)).toBe(false);
  });

  it("rejects strings, null, undefined, and booleans", () => {
    expect(isValidSubmittedRating("3")).toBe(false);
    expect(isValidSubmittedRating(null)).toBe(false);
    expect(isValidSubmittedRating(undefined)).toBe(false);
    expect(isValidSubmittedRating(true)).toBe(false);
    expect(isValidSubmittedRating(false)).toBe(false);
  });

  it("respects a custom max override", () => {
    expect(isValidSubmittedRating(8, 10)).toBe(true);
    expect(isValidSubmittedRating(11, 10)).toBe(false);
  });
});
