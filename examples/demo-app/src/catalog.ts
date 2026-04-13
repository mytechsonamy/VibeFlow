/**
 * Product catalog for the VibeFlow demo project.
 *
 * Implements the CAT-* requirements from docs/PRD.md §3.1:
 *   CAT-001  — a product has id, name, sku, priceMinor, currency, categoryId
 *   CAT-002  — SKUs are unique across the catalog
 *   CAT-003  — products are grouped into categories with a max depth of 3
 *   CAT-004  — search is case-insensitive and matches name + sku prefix
 *   CAT-005  — listProducts is paginated (default pageSize = 25)
 *
 * The implementation is intentionally small so a reader can walk the full
 * loop (PRD → scenarios → tests → coverage → release decision) in one sitting.
 * Real production code would live behind a data-access layer; here the
 * repository is an in-memory Map keyed by product id.
 */

export type Currency = "USD" | "EUR" | "GBP";

export interface Product {
  readonly id: string;
  readonly sku: string;
  readonly name: string;
  /** Price in minor units (cents / pence) — never a float. */
  readonly priceMinor: number;
  readonly currency: Currency;
  readonly categoryId: string;
}

export interface Category {
  readonly id: string;
  readonly name: string;
  readonly parentId: string | null;
}

export interface ListOptions {
  readonly page?: number;
  readonly pageSize?: number;
  readonly categoryId?: string;
}

export interface ListResult {
  readonly page: number;
  readonly pageSize: number;
  readonly total: number;
  readonly items: readonly Product[];
}

export class CatalogError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CatalogError";
  }
}

const MAX_CATEGORY_DEPTH = 3;
const DEFAULT_PAGE_SIZE = 25;

export class ProductCatalog {
  private readonly products = new Map<string, Product>();
  private readonly skuIndex = new Map<string, string>(); // sku → id
  private readonly categories = new Map<string, Category>();

  // ---- CAT-003: category management with depth cap -----------------------

  addCategory(category: Category): void {
    if (category.parentId !== null && !this.categories.has(category.parentId)) {
      throw new CatalogError(
        `parent category ${category.parentId} does not exist`,
      );
    }
    const depth = this.computeCategoryDepth(category.parentId);
    if (depth >= MAX_CATEGORY_DEPTH) {
      throw new CatalogError(
        `category depth limit exceeded (max ${MAX_CATEGORY_DEPTH})`,
      );
    }
    if (this.categories.has(category.id)) {
      throw new CatalogError(`category ${category.id} already exists`);
    }
    this.categories.set(category.id, category);
  }

  private computeCategoryDepth(parentId: string | null): number {
    let depth = 0;
    let cursor: string | null = parentId;
    while (cursor !== null) {
      const parent = this.categories.get(cursor);
      if (parent === undefined) break;
      depth += 1;
      cursor = parent.parentId;
    }
    return depth;
  }

  // ---- CAT-001 / CAT-002: product add with unique-SKU check --------------

  addProduct(product: Product): void {
    if (product.priceMinor < 0 || !Number.isInteger(product.priceMinor)) {
      throw new CatalogError(
        `priceMinor must be a non-negative integer (got ${product.priceMinor})`,
      );
    }
    if (!this.categories.has(product.categoryId)) {
      throw new CatalogError(
        `category ${product.categoryId} does not exist`,
      );
    }
    if (this.skuIndex.has(product.sku)) {
      throw new CatalogError(`sku ${product.sku} already exists`);
    }
    if (this.products.has(product.id)) {
      throw new CatalogError(`product id ${product.id} already exists`);
    }
    this.products.set(product.id, product);
    this.skuIndex.set(product.sku, product.id);
  }

  getProduct(id: string): Product | undefined {
    return this.products.get(id);
  }

  // ---- CAT-004: case-insensitive name + sku prefix search ----------------

  search(query: string): readonly Product[] {
    const needle = query.trim().toLowerCase();
    if (needle.length === 0) return [];
    const matches: Product[] = [];
    for (const p of this.products.values()) {
      if (
        p.name.toLowerCase().includes(needle) ||
        p.sku.toLowerCase().startsWith(needle)
      ) {
        matches.push(p);
      }
    }
    return matches;
  }

  // ---- CAT-005: paginated listing ----------------------------------------

  listProducts(options: ListOptions = {}): ListResult {
    const page = options.page ?? 1;
    const pageSize = options.pageSize ?? DEFAULT_PAGE_SIZE;
    if (page < 1 || !Number.isInteger(page)) {
      throw new CatalogError(`page must be a positive integer (got ${page})`);
    }
    if (pageSize < 1 || pageSize > 100 || !Number.isInteger(pageSize)) {
      throw new CatalogError(
        `pageSize must be an integer in [1, 100] (got ${pageSize})`,
      );
    }

    const source = options.categoryId
      ? [...this.products.values()].filter(
          (p) => p.categoryId === options.categoryId,
        )
      : [...this.products.values()];

    const total = source.length;
    const start = (page - 1) * pageSize;
    const items = source.slice(start, start + pageSize);
    return { page, pageSize, total, items };
  }
}
