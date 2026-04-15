import { notFound } from "next/navigation";
import { getProduct, formatMoney } from "@/lib/catalog";
import { submitReviewFormAction } from "@/actions/submit-review";
import { RatingPicker } from "@/components/rating-picker";

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
      {/* submitReviewFormAction wraps submitReviewAction and swallows
          the return so Next's form action type (void | Promise<void>)
          is satisfied. submitReviewAction itself is covered directly
          by tests/action.test.ts. */}
      <form action={submitReviewFormAction}>
        <input type="hidden" name="productId" value={product.id} />
        <label>
          Rating
          <RatingPicker name="rating" max={5} defaultValue={5} />
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
