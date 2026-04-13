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
export declare function extractTokens(root: FigmaNode): TokenSet;
