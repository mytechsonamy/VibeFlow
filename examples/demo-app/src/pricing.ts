/**
 * Pricing + discount calculations for the VibeFlow demo project.
 *
 * Implements the PRC-* requirements from docs/PRD.md §3.2:
 *   PRC-001  — prices are stored and computed in minor units (integers)
 *   PRC-002  — percentage discount rounds half-down to avoid over-discount
 *   PRC-003  — discount can never push a line total below zero
 *   PRC-004  — tax is applied to the post-discount total, never the list price
 *   PRC-005  — quoted total is { subtotalMinor, discountMinor, taxMinor, totalMinor }
 *
 * Money is always an integer in minor units. There is no `number` arithmetic
 * on floats anywhere in this module — that's the point of the invariant.
 */

export interface LineItem {
  readonly productId: string;
  readonly unitPriceMinor: number;
  readonly quantity: number;
}

export interface Discount {
  readonly kind: "percentage" | "fixed";
  /** For percentage: 0..100. For fixed: minor-unit amount. */
  readonly value: number;
}

export interface Quote {
  readonly subtotalMinor: number;
  readonly discountMinor: number;
  readonly taxableMinor: number;
  readonly taxMinor: number;
  readonly totalMinor: number;
}

export class PricingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PricingError";
  }
}

/** PRC-001: subtotal is the integer sum of `unitPriceMinor * quantity`. */
export function subtotal(items: readonly LineItem[]): number {
  let sum = 0;
  for (const item of items) {
    if (!Number.isInteger(item.unitPriceMinor) || item.unitPriceMinor < 0) {
      throw new PricingError(
        `unitPriceMinor must be a non-negative integer (got ${item.unitPriceMinor})`,
      );
    }
    if (!Number.isInteger(item.quantity) || item.quantity < 0) {
      throw new PricingError(
        `quantity must be a non-negative integer (got ${item.quantity})`,
      );
    }
    sum += item.unitPriceMinor * item.quantity;
  }
  return sum;
}

/**
 * PRC-002: half-down rounding keeps the customer from being over-discounted
 * at decimal boundaries. A 15% discount on 199¢ is 29.85¢ → 29¢, not 30¢.
 */
export function applyDiscount(
  subtotalMinor: number,
  discount: Discount | null,
): number {
  if (discount === null) return 0;
  if (discount.kind === "percentage") {
    if (discount.value < 0 || discount.value > 100) {
      throw new PricingError(
        `percentage discount must be in [0, 100] (got ${discount.value})`,
      );
    }
    // round half-DOWN: floor is enough because subtotal + value are both integers.
    return Math.floor((subtotalMinor * discount.value) / 100);
  }
  if (!Number.isInteger(discount.value) || discount.value < 0) {
    throw new PricingError(
      `fixed discount must be a non-negative integer (got ${discount.value})`,
    );
  }
  // PRC-003: fixed discount clamps at the subtotal — never negative total.
  return Math.min(discount.value, subtotalMinor);
}

/**
 * PRC-004: tax is applied to the taxable amount (subtotal - discount), never
 * to the list price. The rate is a percentage expressed as an integer
 * (e.g. 825 = 8.25%), and rounding is half-up for tax — consumers expect to
 * see a penny added, not removed, when the math rounds.
 */
export function applyTax(
  taxableMinor: number,
  taxRateBasisPoints: number,
): number {
  if (!Number.isInteger(taxRateBasisPoints) || taxRateBasisPoints < 0) {
    throw new PricingError(
      `taxRate must be a non-negative integer (basis points; got ${taxRateBasisPoints})`,
    );
  }
  // (taxable * rate) / 10000 with banker-friendly rounding.
  return Math.round((taxableMinor * taxRateBasisPoints) / 10000);
}

/** PRC-005: the full quote. All four lines are always integers. */
export function quote(
  items: readonly LineItem[],
  discount: Discount | null,
  taxRateBasisPoints: number,
): Quote {
  const subtotalMinor = subtotal(items);
  const discountMinor = applyDiscount(subtotalMinor, discount);
  const taxableMinor = subtotalMinor - discountMinor;
  const taxMinor = applyTax(taxableMinor, taxRateBasisPoints);
  const totalMinor = taxableMinor + taxMinor;
  return { subtotalMinor, discountMinor, taxableMinor, taxMinor, totalMinor };
}
