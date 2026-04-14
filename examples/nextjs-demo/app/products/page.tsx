import Link from "next/link";
import { listProducts, formatMoney } from "@/lib/catalog";

export default function ProductsPage() {
  const products = listProducts();
  return (
    <section>
      <h1>Products</h1>
      <ul>
        {products.map((p) => (
          <li key={p.id}>
            <Link href={`/products/${p.id}`}>
              {p.name} — {formatMoney(p.priceMinor, p.currency)}
            </Link>
          </li>
        ))}
      </ul>
    </section>
  );
}
