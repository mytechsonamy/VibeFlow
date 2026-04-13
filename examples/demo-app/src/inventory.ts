/**
 * Inventory tracking for the VibeFlow demo project.
 *
 * Implements the INV-* requirements from docs/PRD.md §3.3:
 *   INV-001  — stock is tracked per (productId, warehouseId) pair
 *   INV-002  — reserving stock decrements available but not on-hand
 *   INV-003  — committing a reservation decrements on-hand
 *   INV-004  — releasing a reservation returns availability without touching on-hand
 *   INV-005  — reserving more than available raises InsufficientStockError
 *
 * `available` = `onHand` - `reserved`. The two counters are kept independent
 * so concurrent readers see a consistent "available for sale" view even
 * while a purchase is mid-commit.
 */

export interface StockEntry {
  readonly productId: string;
  readonly warehouseId: string;
  readonly onHand: number;
  readonly reserved: number;
}

export class InsufficientStockError extends Error {
  constructor(
    public readonly productId: string,
    public readonly warehouseId: string,
    public readonly requested: number,
    public readonly available: number,
  ) {
    super(
      `insufficient stock: product=${productId} warehouse=${warehouseId} requested=${requested} available=${available}`,
    );
    this.name = "InsufficientStockError";
  }
}

export class InventoryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InventoryError";
  }
}

interface MutableStock {
  onHand: number;
  reserved: number;
}

function key(productId: string, warehouseId: string): string {
  return `${productId}::${warehouseId}`;
}

export class Inventory {
  private readonly stock = new Map<string, MutableStock>();

  // INV-001: initial seed + upsert
  setOnHand(productId: string, warehouseId: string, onHand: number): void {
    if (!Number.isInteger(onHand) || onHand < 0) {
      throw new InventoryError(
        `onHand must be a non-negative integer (got ${onHand})`,
      );
    }
    const k = key(productId, warehouseId);
    const existing = this.stock.get(k);
    if (existing) {
      if (onHand < existing.reserved) {
        throw new InventoryError(
          `cannot set onHand below reserved (onHand=${onHand} reserved=${existing.reserved})`,
        );
      }
      existing.onHand = onHand;
    } else {
      this.stock.set(k, { onHand, reserved: 0 });
    }
  }

  get(productId: string, warehouseId: string): StockEntry {
    const k = key(productId, warehouseId);
    const entry = this.stock.get(k);
    if (!entry) {
      return { productId, warehouseId, onHand: 0, reserved: 0 };
    }
    return {
      productId,
      warehouseId,
      onHand: entry.onHand,
      reserved: entry.reserved,
    };
  }

  available(productId: string, warehouseId: string): number {
    const entry = this.get(productId, warehouseId);
    return entry.onHand - entry.reserved;
  }

  // INV-002 + INV-005: reserve decrements available; throws when insufficient.
  reserve(productId: string, warehouseId: string, quantity: number): void {
    this.assertQuantity(quantity);
    const k = key(productId, warehouseId);
    const entry = this.stock.get(k) ?? { onHand: 0, reserved: 0 };
    const available = entry.onHand - entry.reserved;
    if (quantity > available) {
      throw new InsufficientStockError(
        productId,
        warehouseId,
        quantity,
        available,
      );
    }
    entry.reserved += quantity;
    this.stock.set(k, entry);
  }

  // INV-003: commit a previous reservation — onHand drops, reserved drops.
  commit(productId: string, warehouseId: string, quantity: number): void {
    this.assertQuantity(quantity);
    const k = key(productId, warehouseId);
    const entry = this.stock.get(k);
    if (!entry || entry.reserved < quantity) {
      throw new InventoryError(
        `cannot commit ${quantity}: reserved=${entry?.reserved ?? 0}`,
      );
    }
    entry.onHand -= quantity;
    entry.reserved -= quantity;
  }

  // INV-004: release — reserved drops; onHand unchanged.
  release(productId: string, warehouseId: string, quantity: number): void {
    this.assertQuantity(quantity);
    const k = key(productId, warehouseId);
    const entry = this.stock.get(k);
    if (!entry || entry.reserved < quantity) {
      throw new InventoryError(
        `cannot release ${quantity}: reserved=${entry?.reserved ?? 0}`,
      );
    }
    entry.reserved -= quantity;
  }

  private assertQuantity(quantity: number): void {
    if (!Number.isInteger(quantity) || quantity <= 0) {
      throw new InventoryError(
        `quantity must be a positive integer (got ${quantity})`,
      );
    }
  }
}
