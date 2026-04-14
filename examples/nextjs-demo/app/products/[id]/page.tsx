import { notFound } from "next/navigation";
import { getProduct, formatMoney } from "@/lib/catalog";
import { submitReviewAction } from "@/actions/submit-review";

type PageProps = { params: { id: string } };

export default function ProductDetailPage({ params }: PageProps) {
  const product = getProduct(params.id);
  if (!product) {
    notFound();
  }
  return (
    <article>
      <h1>{product.name}</h1>
      <p>{formatMoney(product.priceMinor, product.currency)}</p>
      <p>{product.description}</p>

      <h2>Leave a review</h2>
      <form action={submitReviewAction}>
        <input type="hidden" name="productId" value={product.id} />
        <label>
          Rating (1-5)
          <input name="rating" type="number" min={1} max={5} required />
        </label>
        <label>
          Review
          <textarea name="text" minLength={10} maxLength={500} required />
        </label>
        <button type="submit">Submit review</button>
      </form>
    </article>
  );
}
