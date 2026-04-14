import { describe, it, expect } from "vitest";
import { getProduct, listProducts, formatMoney } from "../lib/catalog";

describe("catalog — PROD-001 shape", () => {
  it("every product has the six required fields with the right types", () => {
    for (const p of listProducts()) {
      expect(typeof p.id).toBe("string");
      expect(typeof p.name).toBe("string");
      expect(Number.isInteger(p.priceMinor)).toBe(true);
      expect(p.priceMinor).toBeGreaterThanOrEqual(0);
      expect(["USD", "EUR", "GBP"]).toContain(p.currency);
      expect(typeof p.description).toBe("string");
      expect(p.description.length).toBeGreaterThanOrEqual(10);
      expect(p.description.length).toBeLessThanOrEqual(500);
    }
  });
});

describe("catalog — PROD-002 getProduct", () => {
  it("returns the product for a known id", () => {
    const product = getProduct("p-headphones");
    expect(product).toBeDefined();
    expect(product?.name).toBe("Wireless Headphones");
  });

  it("returns undefined for an unknown id, never throws", () => {
    expect(() => getProduct("no-such-id")).not.toThrow();
    expect(getProduct("no-such-id")).toBeUndefined();
  });

  it("returns undefined for the empty string", () => {
    expect(getProduct("")).toBeUndefined();
  });
});

describe("catalog — PROD-003 listProducts ordering", () => {
  it("returns products in stable alphabetical order by name", () => {
    const names = listProducts().map((p) => p.name);
    const sorted = [...names].sort((a, b) => a.localeCompare(b));
    expect(names).toEqual(sorted);
  });

  it("listing twice returns the same ordering", () => {
    const first = listProducts().map((p) => p.id);
    const second = listProducts().map((p) => p.id);
    expect(first).toEqual(second);
  });
});

describe("catalog — PROD-004 currency filter", () => {
  it("returns only USD products when filtered on USD", () => {
    const products = listProducts({ currency: "USD" });
    expect(products.length).toBeGreaterThan(0);
    expect(products.every((p) => p.currency === "USD")).toBe(true);
  });

  it("returns only EUR products when filtered on EUR", () => {
    const products = listProducts({ currency: "EUR" });
    expect(products.length).toBeGreaterThan(0);
    expect(products.every((p) => p.currency === "EUR")).toBe(true);
  });

  it("returns all products when no filter is given", () => {
    expect(listProducts().length).toBeGreaterThanOrEqual(3);
  });
});

describe("catalog — formatMoney helper", () => {
  it("formats USD with the dollar sign and two decimals", () => {
    expect(formatMoney(12999, "USD")).toBe("$129.99");
  });

  it("formats EUR with the euro sign", () => {
    expect(formatMoney(6500, "EUR")).toBe("€65.00");
  });

  it("formats GBP with the pound sign", () => {
    expect(formatMoney(3499, "GBP")).toBe("£34.99");
  });

  it("rejects a non-integer priceMinor (INV-MONEY-INTEGER)", () => {
    expect(() => formatMoney(1.5, "USD")).toThrow(/integer/);
  });

  it("rejects a negative priceMinor", () => {
    expect(() => formatMoney(-1, "USD")).toThrow(/non-negative/);
  });
});
