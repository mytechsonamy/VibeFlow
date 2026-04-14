import { describe, it, expect, beforeEach } from "vitest";
import { submitReviewAction } from "../actions/submit-review";
import { __resetReviewsForTests } from "../lib/reviews";

function makeForm(fields: Record<string, string>): FormData {
  const fd = new FormData();
  for (const [k, v] of Object.entries(fields)) {
    fd.set(k, v);
  }
  return fd;
}

beforeEach(() => {
  __resetReviewsForTests();
});

describe("submitReviewAction — ACT-001 missing fields", () => {
  it("rejects when productId is missing", async () => {
    const r = await submitReviewAction(makeForm({ rating: "5", text: "solid purchase overall" }));
    expect(r).toEqual({ ok: false, error: "missing field productId" });
  });

  it("rejects when rating is missing", async () => {
    const r = await submitReviewAction(
      makeForm({ productId: "p-headphones", text: "solid purchase overall" }),
    );
    expect(r).toEqual({ ok: false, error: "missing field rating" });
  });

  it("rejects when text is missing", async () => {
    const r = await submitReviewAction(
      makeForm({ productId: "p-headphones", rating: "5" }),
    );
    expect(r).toEqual({ ok: false, error: "missing field text" });
  });
});

describe("submitReviewAction — ACT-002 unknown product", () => {
  it("rejects an unknown productId with a stable error string", async () => {
    const r = await submitReviewAction(
      makeForm({ productId: "p-does-not-exist", rating: "5", text: "solid purchase overall" }),
    );
    expect(r).toEqual({ ok: false, error: "unknown product" });
  });
});

describe("submitReviewAction — ACT-003 happy path", () => {
  it("returns { ok: true, review } with a fully-formed Review on success", async () => {
    const r = await submitReviewAction(
      makeForm({
        productId: "p-headphones",
        rating: "5",
        text: "  excellent noise cancellation for long flights  ",
      }),
    );
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.review.productId).toBe("p-headphones");
      expect(r.review.rating).toBe(5);
      expect(r.review.text).toBe("excellent noise cancellation for long flights");
      expect(r.review.id).toMatch(/^rev-p-headphones-\d+$/);
      expect(() => new Date(r.review.createdAt)).not.toThrow();
    }
  });
});

describe("submitReviewAction — ACT-004 validation failures never throw", () => {
  it("rejects rating=10 without throwing", async () => {
    const r = await submitReviewAction(
      makeForm({ productId: "p-headphones", rating: "10", text: "solid purchase overall" }),
    );
    expect(r).toEqual({ ok: false, error: "rating must be integer 1-5" });
  });

  it("rejects an overly short review", async () => {
    const r = await submitReviewAction(
      makeForm({ productId: "p-headphones", rating: "4", text: "short" }),
    );
    expect(r).toEqual({ ok: false, error: "text too short" });
  });

  it("rejects a profane review", async () => {
    const r = await submitReviewAction(
      makeForm({ productId: "p-backpack", rating: "3", text: "this is FORBIDDEN content indeed" }),
    );
    expect(r).toEqual({ ok: false, error: "text contains forbidden words" });
  });

  it("rejects a non-numeric rating", async () => {
    const r = await submitReviewAction(
      makeForm({ productId: "p-headphones", rating: "abc", text: "solid purchase overall" }),
    );
    expect(r).toEqual({ ok: false, error: "rating must be integer 1-5" });
  });
});
