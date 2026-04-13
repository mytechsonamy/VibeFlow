import { TokenSet } from "./tokens.js";
/**
 * Emit human-readable CSS + Tailwind config from an extracted TokenSet.
 *
 * The output is deliberately framework-neutral: both emitters produce plain
 * strings so the caller decides how to deliver them (write to disk, put in
 * a PR, paste into a style guide). Every color, typography, and spacing
 * token becomes a predictable identifier — tests pin the exact shape so we
 * don't drift into design-system bikeshedding on every edit.
 */
export interface StyleOutput {
    readonly css: string;
    readonly tailwind: string;
}
export declare function generateStyles(tokens: TokenSet): StyleOutput;
export declare function generateCss(tokens: TokenSet): string;
export declare function generateTailwind(tokens: TokenSet): string;
