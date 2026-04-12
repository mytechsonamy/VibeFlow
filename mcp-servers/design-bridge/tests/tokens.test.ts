import { describe, expect, it } from "vitest";
import { extractTokens } from "../src/tokens.js";
import { FigmaNode } from "../src/frames.js";

describe("extractTokens — colors", () => {
  it("collects unique SOLID fills and dedupes across nodes", () => {
    const root: FigmaNode = {
      id: "0:0",
      children: [
        {
          id: "1:1",
          fills: [{ type: "SOLID", color: { r: 1, g: 0, b: 0, a: 1 } }],
        },
        {
          id: "2:2",
          fills: [{ type: "SOLID", color: { r: 1, g: 0, b: 0, a: 1 } }],
        },
        {
          id: "3:3",
          fills: [{ type: "SOLID", color: { r: 0, g: 1, b: 0, a: 1 } }],
        },
      ],
    };
    const t = extractTokens(root);
    expect(t.colors).toHaveLength(2);
    const red = t.colors.find((c) => c.hex === "#ff0000ff")!;
    expect(red.sources.sort()).toEqual(["1:1", "2:2"]);
  });

  it("applies paint opacity × color.a to the effective alpha", () => {
    const root: FigmaNode = {
      id: "0:0",
      fills: [
        { type: "SOLID", color: { r: 0, g: 0, b: 0, a: 0.5 }, opacity: 0.5 },
      ],
    };
    const t = extractTokens(root);
    expect(t.colors[0]!.a).toBeCloseTo(0.25, 2);
    // 0.25 * 255 = 63.75 → 0x40
    expect(t.colors[0]!.hex).toBe("#00000040");
  });

  it("ignores non-SOLID paints (gradients, images)", () => {
    const root: FigmaNode = {
      id: "0:0",
      fills: [
        { type: "GRADIENT_LINEAR", color: { r: 1, g: 1, b: 1, a: 1 } },
      ],
    };
    expect(extractTokens(root).colors).toEqual([]);
  });

  it("collects stroke colors as well as fills", () => {
    const root: FigmaNode = {
      id: "0:0",
      strokes: [{ type: "SOLID", color: { r: 0, g: 0, b: 1, a: 1 } }],
    };
    expect(extractTokens(root).colors[0]!.hex).toBe("#0000ffff");
  });
});

describe("extractTokens — typography", () => {
  it("dedupes identical text styles", () => {
    const root: FigmaNode = {
      id: "0:0",
      children: [
        {
          id: "1:1",
          style: {
            fontFamily: "Inter",
            fontWeight: 500,
            fontSize: 16,
            lineHeightPx: 24,
          },
        },
        {
          id: "2:2",
          style: {
            fontFamily: "Inter",
            fontWeight: 500,
            fontSize: 16,
            lineHeightPx: 24,
          },
        },
        {
          id: "3:3",
          style: {
            fontFamily: "Inter",
            fontWeight: 700,
            fontSize: 24,
            lineHeightPx: 32,
          },
        },
      ],
    };
    const t = extractTokens(root);
    expect(t.typography).toHaveLength(2);
    const body = t.typography.find((tt) => tt.fontSize === 16)!;
    expect(body.sources.sort()).toEqual(["1:1", "2:2"]);
  });

  it("skips nodes with no font family", () => {
    const root: FigmaNode = {
      id: "0:0",
      style: { fontSize: 12 },
    };
    expect(extractTokens(root).typography).toEqual([]);
  });
});

describe("extractTokens — spacing", () => {
  it("collects itemSpacing + paddings from AUTO_LAYOUT frames", () => {
    const root: FigmaNode = {
      id: "0:0",
      layoutMode: "HORIZONTAL",
      itemSpacing: 8,
      paddingLeft: 16,
      paddingRight: 16,
      paddingTop: 12,
      paddingBottom: 12,
    };
    const t = extractTokens(root);
    const names = t.spacing.map((s) => `${s.name}-${s.valuePx}`).sort();
    expect(names).toContain("itemSpacing-8");
    expect(names).toContain("paddingLeft-16");
    expect(names).toContain("paddingTop-12");
  });

  it("ignores frames without a layoutMode", () => {
    const root: FigmaNode = { id: "0:0", itemSpacing: 8 };
    expect(extractTokens(root).spacing).toEqual([]);
  });

  it("ignores zero or negative spacing values", () => {
    const root: FigmaNode = {
      id: "0:0",
      layoutMode: "VERTICAL",
      itemSpacing: 0,
      paddingLeft: -1,
    };
    expect(extractTokens(root).spacing).toEqual([]);
  });
});
