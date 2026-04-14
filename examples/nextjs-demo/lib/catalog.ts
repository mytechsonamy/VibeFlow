// In-memory product catalog for the Next.js demo.
//
// This module is the "source of truth" referenced by the RSC pages at
// app/products/**. It has no network, no database — just a frozen list
// of products and two public helpers. Every requirement in PRD §3.1
// (PROD-*) is covered by tests in tests/catalog.test.ts.

export type Currency = "USD" | "EUR" | "GBP";

export interface Product {
  readonly id: string;
  readonly name: string;
  readonly priceMinor: number; // integer, minor currency units
  readonly currency: Currency;
  readonly description: string; // 10..500 chars
}

const PRODUCTS: readonly Product[] = Object.freeze([
  Object.freeze({
    id: "p-headphones",
    name: "Wireless Headphones",
    priceMinor: 12999,
    currency: "USD" as Currency,
    description:
      "Over-ear wireless headphones with 40 hours of battery life and active noise cancellation.",
  }),
  Object.freeze({
    id: "p-backpack",
    name: "Everyday Backpack",
    priceMinor: 6500,
    currency: "EUR" as Currency,
    description:
      "A 20L backpack with a padded laptop sleeve and a water-resistant exterior.",
  }),
  Object.freeze({
    id: "p-kettle",
    name: "Electric Kettle",
    priceMinor: 3499,
    currency: "GBP" as Currency,
    description:
      "1.7L stainless steel kettle with rapid boil and an auto-off safety cutoff.",
  }),
]);

export interface ListProductsOptions {
  readonly currency?: Currency;
}

// PROD-003 — stable alphabetical order by name.
// PROD-004 — optional currency filter.
export function listProducts(opts: ListProductsOptions = {}): readonly Product[] {
  const filtered = opts.currency
    ? PRODUCTS.filter((p) => p.currency === opts.currency)
    : PRODUCTS;
  return [...filtered].sort((a, b) => a.name.localeCompare(b.name));
}

// PROD-002 — returns undefined for unknown ids. Never throws.
export function getProduct(id: string): Product | undefined {
  return PRODUCTS.find((p) => p.id === id);
}

export function formatMoney(priceMinor: number, currency: Currency): string {
  if (!Number.isInteger(priceMinor) || priceMinor < 0) {
    throw new Error("priceMinor must be a non-negative integer");
  }
  const major = priceMinor / 100;
  const symbol = currency === "USD" ? "$" : currency === "EUR" ? "€" : "£";
  return `${symbol}${major.toFixed(2)}`;
}
