import { describe, expect, it } from "vitest";
import { generateCss, generateTailwind, generateStyles } from "../src/styles.js";
import { TokenSet } from "../src/tokens.js";

function mkTokens(partial: Partial<TokenSet> = {}): TokenSet {
  return {
    colors: [],
    typography: [],
    spacing: [],
    scannedAt: "2026-04-12T00:00:00Z",
    nodesVisited: 0,
    ...partial,
  };
}

describe("generateCss", () => {
  it("emits :root custom properties in a stable order", () => {
    const css = generateCss(
      mkTokens({
        colors: [
          { hex: "#ff0000ff", r: 1, g: 0, b: 0, a: 1, sources: ["1"] },
          { hex: "#00ff00ff", r: 0, g: 1, b: 0, a: 1, sources: ["2"] },
        ],
        spacing: [
          { name: "itemSpacing", valuePx: 8, sources: ["3"] },
        ],
        typography: [
          {
            fontFamily: "Inter",
            fontWeight: 400,
            fontSize: 16,
            lineHeightPx: 24,
            letterSpacing: null,
            sources: ["4"],
          },
        ],
      }),
    );
    expect(css).toContain(":root {");
    expect(css).toContain("--color-1: #ff0000ff;");
    expect(css).toContain("--color-2: #00ff00ff;");
    expect(css).toContain("--space-itemSpacing-8: 8px;");
    expect(css).toContain('--font-1-family: "Inter";');
    expect(css).toContain("--font-1-size: 16px;");
    expect(css).toContain("--font-1-line-height: 24px;");
    expect(css.endsWith("}\n")).toBe(true);
  });

  it("skips line-height when null", () => {
    const css = generateCss(
      mkTokens({
        typography: [
          {
            fontFamily: "Inter",
            fontWeight: 400,
            fontSize: 12,
            lineHeightPx: null,
            letterSpacing: null,
            sources: ["1"],
          },
        ],
      }),
    );
    expect(css).not.toContain("line-height");
  });
});

describe("generateTailwind", () => {
  it("produces a module.exports config with theme.extend", () => {
    const tw = generateTailwind(
      mkTokens({
        colors: [
          { hex: "#112233ff", r: 0.06, g: 0.13, b: 0.2, a: 1, sources: ["1"] },
        ],
        spacing: [{ name: "itemSpacing", valuePx: 4, sources: ["2"] }],
        typography: [
          {
            fontFamily: "Inter",
            fontWeight: 400,
            fontSize: 14,
            lineHeightPx: 20,
            letterSpacing: null,
            sources: ["3"],
          },
        ],
      }),
    );
    expect(tw).toContain("module.exports = {");
    expect(tw).toContain('"c1": "#112233ff"');
    expect(tw).toContain('"itemSpacing-4": "4px"');
    expect(tw).toContain('"family-1": ["Inter"]');
    expect(tw).toContain('"t1": ["14px", { lineHeight: "20px" }]');
  });
});

describe("generateStyles", () => {
  it("returns both css and tailwind outputs", () => {
    const out = generateStyles(mkTokens());
    expect(out).toHaveProperty("css");
    expect(out).toHaveProperty("tailwind");
    expect(out.css.startsWith(":root")).toBe(true);
    expect(out.tailwind.startsWith("//")).toBe(true);
  });
});
