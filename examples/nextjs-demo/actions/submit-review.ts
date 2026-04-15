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
//
// Returns a discriminated result so the test suite can assert the
// success + failure shapes symmetrically. The page itself wraps this
// via `submitReviewFormAction` below — Next 14's `<form action={...}>`
// typing requires a void-returning action, so the void wrapper is the
// one actually mounted on the form.
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

// Void wrapper consumed by <form action={...}> in the product detail
// page. Next 14's form action typing is
// `(formData: FormData) => void | Promise<void>`; a discriminated
// result type is not assignable. The wrapper calls submitReviewAction
// and swallows the result — a real app would call revalidatePath()
// or redirect() here to surface the outcome to the user. The demo
// keeps it minimal because the actual assertion story lives in
// tests/action.test.ts against submitReviewAction directly.
export async function submitReviewFormAction(formData: FormData): Promise<void> {
  await submitReviewAction(formData);
}
