import { FigmaNode } from "./frames.js";

/**
 * Token extraction: walks a Figma node tree and collects the visual
 * primitives that design systems usually formalize as tokens. Three
 * categories today:
 *
 *   - colors     — unique SOLID fill/stroke paints (normalized to 8-digit
 *                  hex including alpha)
 *   - typography — unique `style` blobs (family, weight, size, line-height)
 *   - spacing    — unique `itemSpacing` / paddings from AUTO_LAYOUT frames
 *
 * Every token carries a `sources` list: the node IDs that produced it, so
 * design reviewers can jump straight to the offending / approving frame.
 */

export interface ColorToken {
  readonly hex: string;
  readonly r: number;
  readonly g: number;
  readonly b: number;
  readonly a: number;
  readonly sources: readonly string[];
}

export interface TypographyToken {
  readonly fontFamily: string;
  readonly fontWeight: number;
  readonly fontSize: number;
  readonly lineHeightPx: number | null;
  readonly letterSpacing: number | null;
  readonly sources: readonly string[];
}

export interface SpacingToken {
  readonly name: string;
  readonly valuePx: number;
  readonly sources: readonly string[];
}

export interface TokenSet {
  readonly colors: readonly ColorToken[];
  readonly typography: readonly TypographyToken[];
  readonly spacing: readonly SpacingToken[];
  readonly scannedAt: string;
  readonly nodesVisited: number;
}

export function extractTokens(root: FigmaNode): TokenSet {
  const colors = new Map<string, ColorToken>();
  const typography = new Map<string, TypographyToken>();
  const spacing = new Map<string, SpacingToken>();
  let visited = 0;

  const stack: FigmaNode[] = [root];
  while (stack.length > 0) {
    const node = stack.pop()!;
    visited += 1;

    collectFills(node, colors);
    collectStrokes(node, colors);
    collectTypography(node, typography);
    collectSpacing(node, spacing);

    for (const child of node.children ?? []) {
      stack.push(child);
    }
  }

  return {
    colors: [...colors.values()].sort((a, b) => a.hex.localeCompare(b.hex)),
    typography: [...typography.values()].sort((a, b) =>
      `${a.fontFamily}-${a.fontWeight}-${a.fontSize}`.localeCompare(
        `${b.fontFamily}-${b.fontWeight}-${b.fontSize}`,
      ),
    ),
    spacing: [...spacing.values()].sort((a, b) => a.valuePx - b.valuePx),
    scannedAt: new Date().toISOString(),
    nodesVisited: visited,
  };
}

interface SolidPaint {
  type: string;
  color?: { r: number; g: number; b: number; a?: number };
  opacity?: number;
}

function collectFills(node: FigmaNode, into: Map<string, ColorToken>): void {
  const fills = node.fills as SolidPaint[] | undefined;
  if (!Array.isArray(fills)) return;
  for (const f of fills) {
    if (f.type !== "SOLID" || !f.color) continue;
    recordColor(f.color.r, f.color.g, f.color.b, effectiveAlpha(f), node.id, into);
  }
}

function collectStrokes(node: FigmaNode, into: Map<string, ColorToken>): void {
  const strokes = node.strokes as SolidPaint[] | undefined;
  if (!Array.isArray(strokes)) return;
  for (const s of strokes) {
    if (s.type !== "SOLID" || !s.color) continue;
    recordColor(s.color.r, s.color.g, s.color.b, effectiveAlpha(s), node.id, into);
  }
}

function effectiveAlpha(paint: SolidPaint): number {
  const baseAlpha = paint.color?.a ?? 1;
  const opacity = paint.opacity ?? 1;
  return clamp01(baseAlpha * opacity);
}

function recordColor(
  r: number,
  g: number,
  b: number,
  a: number,
  source: string,
  into: Map<string, ColorToken>,
): void {
  const hex = toHex(r, g, b, a);
  const existing = into.get(hex);
  if (existing) {
    into.set(hex, {
      ...existing,
      sources: dedupePush(existing.sources, source),
    });
    return;
  }
  into.set(hex, {
    hex,
    r: round(r),
    g: round(g),
    b: round(b),
    a: round(a),
    sources: [source],
  });
}

interface FigmaStyle {
  fontFamily?: string;
  fontWeight?: number;
  fontSize?: number;
  lineHeightPx?: number;
  letterSpacing?: number;
}

function collectTypography(
  node: FigmaNode,
  into: Map<string, TypographyToken>,
): void {
  const style = node.style as FigmaStyle | undefined;
  if (!style || typeof style !== "object") return;
  if (!style.fontFamily || style.fontSize === undefined) return;

  const token: TypographyToken = {
    fontFamily: style.fontFamily,
    fontWeight: style.fontWeight ?? 400,
    fontSize: style.fontSize,
    lineHeightPx: style.lineHeightPx ?? null,
    letterSpacing: style.letterSpacing ?? null,
    sources: [node.id],
  };
  const key = typographyKey(token);
  const existing = into.get(key);
  if (existing) {
    into.set(key, {
      ...existing,
      sources: dedupePush(existing.sources, node.id),
    });
  } else {
    into.set(key, token);
  }
}

function typographyKey(t: TypographyToken): string {
  return `${t.fontFamily}|${t.fontWeight}|${t.fontSize}|${t.lineHeightPx ?? "-"}|${t.letterSpacing ?? "-"}`;
}

function collectSpacing(
  node: FigmaNode,
  into: Map<string, SpacingToken>,
): void {
  if (node.layoutMode !== "HORIZONTAL" && node.layoutMode !== "VERTICAL") {
    return;
  }
  const candidates: Array<[string, number | undefined]> = [
    ["itemSpacing", node.itemSpacing as number | undefined],
    ["paddingLeft", node.paddingLeft as number | undefined],
    ["paddingRight", node.paddingRight as number | undefined],
    ["paddingTop", node.paddingTop as number | undefined],
    ["paddingBottom", node.paddingBottom as number | undefined],
  ];
  for (const [name, raw] of candidates) {
    if (typeof raw !== "number" || raw <= 0) continue;
    const rounded = Math.round(raw);
    const key = `${name}-${rounded}`;
    const existing = into.get(key);
    if (existing) {
      into.set(key, {
        ...existing,
        sources: dedupePush(existing.sources, node.id),
      });
    } else {
      into.set(key, { name, valuePx: rounded, sources: [node.id] });
    }
  }
}

function toHex(r: number, g: number, b: number, a: number): string {
  const rr = byte(r);
  const gg = byte(g);
  const bb = byte(b);
  const aa = byte(a);
  return `#${rr}${gg}${bb}${aa}`;
}

function byte(v: number): string {
  const n = Math.round(clamp01(v) * 255);
  return n.toString(16).padStart(2, "0");
}

function clamp01(n: number): number {
  if (!Number.isFinite(n)) return 0;
  if (n < 0) return 0;
  if (n > 1) return 1;
  return n;
}

function round(n: number): number {
  return Math.round(n * 1000) / 1000;
}

function dedupePush(xs: readonly string[], v: string): string[] {
  return xs.includes(v) ? [...xs] : [...xs, v];
}
