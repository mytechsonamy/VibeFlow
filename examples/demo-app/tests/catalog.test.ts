import { describe, it, expect, beforeEach } from "vitest";
import { ProductCatalog, CatalogError, Product } from "../src/catalog.js";

function seed(c: ProductCatalog): void {
  c.addCategory({ id: "root", name: "Root", parentId: null });
  c.addCategory({ id: "apparel", name: "Apparel", parentId: "root" });
  c.addCategory({ id: "shirts", name: "Shirts", parentId: "apparel" });
}

function sampleProduct(overrides: Partial<Product> = {}): Product {
  return {
    id: overrides.id ?? "p1",
    sku: overrides.sku ?? "SKU-001",
    name: overrides.name ?? "Cotton Tee",
    priceMinor: overrides.priceMinor ?? 2499,
    currency: overrides.currency ?? "USD",
    categoryId: overrides.categoryId ?? "shirts",
  };
}

describe("ProductCatalog — CAT-001 product shape", () => {
  let catalog: ProductCatalog;
  beforeEach(() => {
    catalog = new ProductCatalog();
    seed(catalog);
  });

  it("adds and retrieves a product by id", () => {
    const p = sampleProduct();
    catalog.addProduct(p);
    expect(catalog.getProduct("p1")).toEqual(p);
  });

  it("rejects a non-integer priceMinor", () => {
    expect(() =>
      catalog.addProduct(sampleProduct({ priceMinor: 24.99 })),
    ).toThrow(CatalogError);
  });

  it("rejects a negative priceMinor", () => {
    expect(() =>
      catalog.addProduct(sampleProduct({ priceMinor: -1 })),
    ).toThrow(CatalogError);
  });

  it("rejects a product in a category that does not exist", () => {
    expect(() =>
      catalog.addProduct(sampleProduct({ categoryId: "ghost" })),
    ).toThrow(CatalogError);
  });
});

describe("ProductCatalog — CAT-002 unique SKUs", () => {
  let catalog: ProductCatalog;
  beforeEach(() => {
    catalog = new ProductCatalog();
    seed(catalog);
  });

  it("rejects a duplicate SKU across products", () => {
    catalog.addProduct(sampleProduct({ id: "p1", sku: "SKU-DUP" }));
    expect(() =>
      catalog.addProduct(sampleProduct({ id: "p2", sku: "SKU-DUP" })),
    ).toThrow(/sku SKU-DUP already exists/);
  });

  it("rejects a duplicate product id", () => {
    catalog.addProduct(sampleProduct({ id: "p1", sku: "A" }));
    expect(() =>
      catalog.addProduct(sampleProduct({ id: "p1", sku: "B" })),
    ).toThrow(/product id p1 already exists/);
  });
});

describe("ProductCatalog — CAT-003 category depth cap", () => {
  it("allows 3 levels below root", () => {
    const c = new ProductCatalog();
    c.addCategory({ id: "root", name: "Root", parentId: null });
    c.addCategory({ id: "L1", name: "L1", parentId: "root" });
    c.addCategory({ id: "L2", name: "L2", parentId: "L1" });
    // depth counts ancestors; L2 is depth 2 → addCategory with parent L2 is depth 3 → reject.
    expect(() =>
      c.addCategory({ id: "L3", name: "L3", parentId: "L2" }),
    ).toThrow(/depth limit/);
  });

  it("rejects a category with a non-existent parent", () => {
    const c = new ProductCatalog();
    expect(() =>
      c.addCategory({ id: "orphan", name: "Orphan", parentId: "ghost" }),
    ).toThrow(/parent category ghost does not exist/);
  });
});

describe("ProductCatalog — CAT-004 search", () => {
  let catalog: ProductCatalog;
  beforeEach(() => {
    catalog = new ProductCatalog();
    seed(catalog);
    catalog.addProduct(sampleProduct({ id: "p1", sku: "TEE-001", name: "Cotton Tee" }));
    catalog.addProduct(
      sampleProduct({ id: "p2", sku: "TEE-002", name: "Linen Tee" }),
    );
    catalog.addProduct(
      sampleProduct({ id: "p3", sku: "SHRT-001", name: "Oxford Shirt" }),
    );
  });

  it("matches on name case-insensitively", () => {
    const results = catalog.search("cotton");
    expect(results.map((p) => p.id)).toEqual(["p1"]);
  });

  it("matches on sku prefix", () => {
    const results = catalog.search("tee-");
    expect(results.map((p) => p.id).sort()).toEqual(["p1", "p2"]);
  });

  it("returns empty for an empty query", () => {
    expect(catalog.search("   ")).toEqual([]);
  });
});

describe("ProductCatalog — CAT-005 pagination", () => {
  let catalog: ProductCatalog;
  beforeEach(() => {
    catalog = new ProductCatalog();
    seed(catalog);
    for (let i = 0; i < 30; i++) {
      catalog.addProduct(
        sampleProduct({
          id: `p${i}`,
          sku: `SKU-${String(i).padStart(3, "0")}`,
          name: `Item ${i}`,
        }),
      );
    }
  });

  it("defaults to pageSize 25 on the first page", () => {
    const r = catalog.listProducts();
    expect(r.pageSize).toBe(25);
    expect(r.items).toHaveLength(25);
    expect(r.total).toBe(30);
  });

  it("returns the tail on page 2", () => {
    const r = catalog.listProducts({ page: 2 });
    expect(r.items).toHaveLength(5);
  });

  it("rejects a page < 1", () => {
    expect(() => catalog.listProducts({ page: 0 })).toThrow(CatalogError);
  });

  it("rejects a pageSize > 100", () => {
    expect(() => catalog.listProducts({ pageSize: 101 })).toThrow(CatalogError);
  });

  it("filters to a category when categoryId is provided", () => {
    const r = catalog.listProducts({ categoryId: "apparel" });
    // none of our 30 products live directly under `apparel` — they live in `shirts`
    expect(r.total).toBe(0);
  });
});
