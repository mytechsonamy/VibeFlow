"use server";

// Server action invoked by app/products/[id]/page.tsx.
//
// Every branch is unit-testable: the FormData input comes straight
// from the browser and the rest is pure TypeScript via lib/reviews +
// lib/catalog. Tests in tests/action.test.ts exercise the action by
// constructing FormData objects directly — no Next runtime required.

import { getProduct } from "@/lib/catalog";
import { persistReview, validateReview, type Review } from "@/lib/reviews";

export type SubmitReviewResult =
  | { readonly ok: true; readonly review: Review }
  | { readonly ok: false; readonly error: string };

// Exported for direct testing. Accepts FormData because Next server
// actions receive FormData (and an optional "previous state" in the
// useFormState case, which this demo does not use).
export async function submitReviewAction(formData: FormData): Promise<SubmitReviewResult> {
  const productId = formData.get("productId");
  if (typeof productId !== "string" || productId.length === 0) {
    return { ok: false, error: "missing field productId" };
  }

  const ratingRaw = formData.get("rating");
  if (ratingRaw === null) {
    return { ok: false, error: "missing field rating" };
  }
  const rating = Number(ratingRaw);

  const text = formData.get("text");
  if (text === null) {
    return { ok: false, error: "missing field text" };
  }

  if (!getProduct(productId)) {
    return { ok: false, error: "unknown product" };
  }

  const validated = validateReview({ rating, text });
  if (!validated.ok) {
    return { ok: false, error: validated.error };
  }

  const review = persistReview({
    productId,
    rating: validated.rating,
    text: validated.text,
  });
  return { ok: true, review };
}
