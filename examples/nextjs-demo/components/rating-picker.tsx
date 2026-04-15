"use client";

// RatingPicker — client component for the review form on the product
// detail page. Owns hover + click state (which forces `"use client"`),
// but every stateless operation lives in lib/rating.ts so vitest can
// unit-test the logic without rendering React.
//
// The surrounding form is still a React Server Component in
// app/products/[id]/page.tsx — the RSC/client boundary runs along
// this file's import. Next.js 14 serializes the props (name, max,
// defaultValue) from the server to the client on initial render.

import { useState } from "react";
import {
  DEFAULT_MAX_RATING,
  clampRating,
  computeDisplay,
  renderStars,
} from "@/lib/rating";

export interface RatingPickerProps {
  readonly name: string;
  readonly max?: number;
  readonly defaultValue?: number;
}

export function RatingPicker({
  name,
  max = DEFAULT_MAX_RATING,
  defaultValue = 0,
}: RatingPickerProps) {
  const [rating, setRating] = useState<number>(() =>
    clampRating(defaultValue, max),
  );
  const [hover, setHover] = useState<number | null>(null);
  const display = computeDisplay(rating, hover);
  const stars = renderStars(display, max);

  return (
    <div role="radiogroup" aria-label="Rating">
      <input type="hidden" name={name} value={rating} />
      {stars.map((char, idx) => {
        const star = idx + 1;
        return (
          <button
            key={star}
            type="button"
            role="radio"
            aria-checked={rating === star}
            aria-label={`${star} of ${max} stars`}
            onMouseEnter={() => setHover(star)}
            onMouseLeave={() => setHover(null)}
            onClick={() => setRating(clampRating(star, max))}
          >
            {char}
          </button>
        );
      })}
    </div>
  );
}
