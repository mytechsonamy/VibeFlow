import { describe, it, expect, beforeEach } from "vitest";
import {
  Inventory,
  InsufficientStockError,
  InventoryError,
} from "../src/inventory.js";

const P = "prod-1";
const W = "wh-east";

describe("Inventory — INV-001 seed + get", () => {
  it("returns a zero entry for unseeded pairs", () => {
    const inv = new Inventory();
    const e = inv.get(P, W);
    expect(e.onHand).toBe(0);
    expect(e.reserved).toBe(0);
  });

  it("seeds onHand and reads it back", () => {
    const inv = new Inventory();
    inv.setOnHand(P, W, 50);
    expect(inv.get(P, W).onHand).toBe(50);
    expect(inv.available(P, W)).toBe(50);
  });

  it("rejects a negative onHand", () => {
    const inv = new Inventory();
    expect(() => inv.setOnHand(P, W, -1)).toThrow(InventoryError);
  });

  it("rejects setOnHand below current reserved", () => {
    const inv = new Inventory();
    inv.setOnHand(P, W, 10);
    inv.reserve(P, W, 6);
    expect(() => inv.setOnHand(P, W, 5)).toThrow(/below reserved/);
  });
});

describe("Inventory — INV-002 reserve decrements available not onHand", () => {
  let inv: Inventory;
  beforeEach(() => {
    inv = new Inventory();
    inv.setOnHand(P, W, 10);
  });

  it("drops available but leaves onHand", () => {
    inv.reserve(P, W, 3);
    expect(inv.available(P, W)).toBe(7);
    expect(inv.get(P, W).onHand).toBe(10);
    expect(inv.get(P, W).reserved).toBe(3);
  });

  it("throws InsufficientStockError when reservation exceeds available", () => {
    inv.reserve(P, W, 10);
    expect(() => inv.reserve(P, W, 1)).toThrow(InsufficientStockError);
  });

  it("rejects a non-positive quantity", () => {
    expect(() => inv.reserve(P, W, 0)).toThrow(InventoryError);
    expect(() => inv.reserve(P, W, -1)).toThrow(InventoryError);
  });
});

describe("Inventory — INV-003 commit decrements onHand", () => {
  it("commits a reserved quantity", () => {
    const inv = new Inventory();
    inv.setOnHand(P, W, 10);
    inv.reserve(P, W, 4);
    inv.commit(P, W, 4);
    expect(inv.get(P, W).onHand).toBe(6);
    expect(inv.get(P, W).reserved).toBe(0);
    expect(inv.available(P, W)).toBe(6);
  });

  it("rejects a commit larger than the current reserve", () => {
    const inv = new Inventory();
    inv.setOnHand(P, W, 10);
    inv.reserve(P, W, 2);
    expect(() => inv.commit(P, W, 3)).toThrow(InventoryError);
  });
});

describe("Inventory — INV-004 release returns availability", () => {
  it("releases a reservation without changing onHand", () => {
    const inv = new Inventory();
    inv.setOnHand(P, W, 10);
    inv.reserve(P, W, 5);
    inv.release(P, W, 3);
    expect(inv.get(P, W).reserved).toBe(2);
    expect(inv.get(P, W).onHand).toBe(10);
    expect(inv.available(P, W)).toBe(8);
  });

  it("rejects releasing more than was reserved", () => {
    const inv = new Inventory();
    inv.setOnHand(P, W, 5);
    inv.reserve(P, W, 2);
    expect(() => inv.release(P, W, 3)).toThrow(InventoryError);
  });
});

describe("Inventory — INV-005 insufficient stock carries detail", () => {
  it("error carries productId + warehouseId + requested + available", () => {
    const inv = new Inventory();
    inv.setOnHand(P, W, 2);
    try {
      inv.reserve(P, W, 5);
      expect.fail("expected InsufficientStockError");
    } catch (err) {
      expect(err).toBeInstanceOf(InsufficientStockError);
      const e = err as InsufficientStockError;
      expect(e.productId).toBe(P);
      expect(e.warehouseId).toBe(W);
      expect(e.requested).toBe(5);
      expect(e.available).toBe(2);
    }
  });
});
