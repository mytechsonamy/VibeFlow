export function extractTokens(root) {
    const colors = new Map();
    const typography = new Map();
    const spacing = new Map();
    let visited = 0;
    const stack = [root];
    while (stack.length > 0) {
        const node = stack.pop();
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
        typography: [...typography.values()].sort((a, b) => `${a.fontFamily}-${a.fontWeight}-${a.fontSize}`.localeCompare(`${b.fontFamily}-${b.fontWeight}-${b.fontSize}`)),
        spacing: [...spacing.values()].sort((a, b) => a.valuePx - b.valuePx),
        scannedAt: new Date().toISOString(),
        nodesVisited: visited,
    };
}
function collectFills(node, into) {
    const fills = node.fills;
    if (!Array.isArray(fills))
        return;
    for (const f of fills) {
        if (f.type !== "SOLID" || !f.color)
            continue;
        recordColor(f.color.r, f.color.g, f.color.b, effectiveAlpha(f), node.id, into);
    }
}
function collectStrokes(node, into) {
    const strokes = node.strokes;
    if (!Array.isArray(strokes))
        return;
    for (const s of strokes) {
        if (s.type !== "SOLID" || !s.color)
            continue;
        recordColor(s.color.r, s.color.g, s.color.b, effectiveAlpha(s), node.id, into);
    }
}
function effectiveAlpha(paint) {
    const baseAlpha = paint.color?.a ?? 1;
    const opacity = paint.opacity ?? 1;
    return clamp01(baseAlpha * opacity);
}
function recordColor(r, g, b, a, source, into) {
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
function collectTypography(node, into) {
    const style = node.style;
    if (!style || typeof style !== "object")
        return;
    if (!style.fontFamily || style.fontSize === undefined)
        return;
    const token = {
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
    }
    else {
        into.set(key, token);
    }
}
function typographyKey(t) {
    return `${t.fontFamily}|${t.fontWeight}|${t.fontSize}|${t.lineHeightPx ?? "-"}|${t.letterSpacing ?? "-"}`;
}
function collectSpacing(node, into) {
    if (node.layoutMode !== "HORIZONTAL" && node.layoutMode !== "VERTICAL") {
        return;
    }
    const candidates = [
        ["itemSpacing", node.itemSpacing],
        ["paddingLeft", node.paddingLeft],
        ["paddingRight", node.paddingRight],
        ["paddingTop", node.paddingTop],
        ["paddingBottom", node.paddingBottom],
    ];
    for (const [name, raw] of candidates) {
        if (typeof raw !== "number" || raw <= 0)
            continue;
        const rounded = Math.round(raw);
        const key = `${name}-${rounded}`;
        const existing = into.get(key);
        if (existing) {
            into.set(key, {
                ...existing,
                sources: dedupePush(existing.sources, node.id),
            });
        }
        else {
            into.set(key, { name, valuePx: rounded, sources: [node.id] });
        }
    }
}
function toHex(r, g, b, a) {
    const rr = byte(r);
    const gg = byte(g);
    const bb = byte(b);
    const aa = byte(a);
    return `#${rr}${gg}${bb}${aa}`;
}
function byte(v) {
    const n = Math.round(clamp01(v) * 255);
    return n.toString(16).padStart(2, "0");
}
function clamp01(n) {
    if (!Number.isFinite(n))
        return 0;
    if (n < 0)
        return 0;
    if (n > 1)
        return 1;
    return n;
}
function round(n) {
    return Math.round(n * 1000) / 1000;
}
function dedupePush(xs, v) {
    return xs.includes(v) ? [...xs] : [...xs, v];
}
//# sourceMappingURL=tokens.js.map