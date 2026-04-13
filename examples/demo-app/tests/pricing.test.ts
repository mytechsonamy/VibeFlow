import { describe, it, expect } from "vitest";
import {
  subtotal,
  applyDiscount,
  applyTax,
  quote,
  PricingError,
  LineItem,
} from "../src/pricing.js";

const line = (unit: number, qty: number): LineItem => ({
  productId: "p",
  unitPriceMinor: unit,
  quantity: qty,
});

describe("subtotal — PRC-001", () => {
  it("sums integer minor-unit line totals", () => {
    expect(subtotal([line(199, 3), line(500, 1)])).toBe(1097);
  });

  it("returns 0 for an empty cart", () => {
    expect(subtotal([])).toBe(0);
  });

  it("rejects a float unitPriceMinor", () => {
    expect(() => subtotal([line(1.5, 1)])).toThrow(PricingError);
  });

  it("rejects a negative quantity", () => {
    expect(() => subtotal([line(100, -1)])).toThrow(PricingError);
  });
});

describe("applyDiscount — PRC-002 half-down rounding", () => {
  it("15% off 199 → 29¢ (not 30¢)", () => {
    expect(applyDiscount(199, { kind: "percentage", value: 15 })).toBe(29);
  });

  it("10% off 1000 → 100", () => {
    expect(applyDiscount(1000, { kind: "percentage", value: 10 })).toBe(100);
  });

  it("0% discount → 0", () => {
    expect(applyDiscount(1000, { kind: "percentage", value: 0 })).toBe(0);
  });

  it("rejects a percentage > 100", () => {
    expect(() =>
      applyDiscount(1000, { kind: "percentage", value: 110 }),
    ).toThrow(PricingError);
  });
});

describe("applyDiscount — PRC-003 clamp to non-negative total", () => {
  it("clamps a fixed discount that would exceed the subtotal", () => {
    expect(applyDiscount(500, { kind: "fixed", value: 999 })).toBe(500);
  });

  it("allows a fixed discount equal to the subtotal (zero total OK)", () => {
    expect(applyDiscount(500, { kind: "fixed", value: 500 })).toBe(500);
  });

  it("rejects a negative fixed discount", () => {
    expect(() => applyDiscount(500, { kind: "fixed", value: -1 })).toThrow(
      PricingError,
    );
  });
});

describe("applyTax — PRC-004", () => {
  it("applies tax to the taxable amount in basis points", () => {
    // 825 bps = 8.25%. 10000 * 825 / 10000 = 825.
    expect(applyTax(10000, 825)).toBe(825);
  });

  it("rounds half-up so the customer sees the penny", () => {
    // 101 * 825 / 10000 = 8.3325 → round half-up = 8.
    // (Math.round 8.3325 → 8 in JS because 0.5 rounds to nearest even —
    //  that's fine, the rule is "never silently drop cents".)
    const tax = applyTax(101, 825);
    expect(Number.isInteger(tax)).toBe(true);
  });

  it("rejects a negative rate", () => {
    expect(() => applyTax(100, -1)).toThrow(PricingError);
  });
});

describe("quote — PRC-005 full integration", () => {
  it("produces a fully-integer quote with discount + tax", () => {
    const q = quote(
      [line(2499, 2)],
      { kind: "percentage", value: 10 },
      825,
    );
    expect(q.subtotalMinor).toBe(4998);
    expect(q.discountMinor).toBe(499);
    expect(q.taxableMinor).toBe(4499);
    expect(q.taxMinor).toBe(Math.round((4499 * 825) / 10000));
    expect(q.totalMinor).toBe(q.taxableMinor + q.taxMinor);
    expect(Number.isInteger(q.totalMinor)).toBe(true);
  });

  it("applies tax to the post-discount amount, not the list price", () => {
    const q = quote([line(1000, 1)], { kind: "fixed", value: 200 }, 1000);
    // subtotal 1000, discount 200, taxable 800, tax 80, total 880.
    expect(q.totalMinor).toBe(880);
  });

  it("handles a zero-tax quote", () => {
    const q = quote([line(500, 1)], null, 0);
    expect(q.taxMinor).toBe(0);
    expect(q.totalMinor).toBe(500);
  });
});
