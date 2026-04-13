export function parseFigmaUrl(url) {
    let parsed;
    try {
        parsed = new URL(url);
    }
    catch {
        throw new Error(`not a valid URL: ${url}`);
    }
    if (!/figma\.com$/.test(parsed.hostname) && parsed.hostname !== "figma.com") {
        throw new Error(`not a figma.com URL: ${parsed.hostname}`);
    }
    // Path: /file/<KEY>/<title> or /design/<KEY>/<title>
    const parts = parsed.pathname.split("/").filter((p) => p !== "");
    const kind = parts[0];
    if (kind !== "file" && kind !== "design") {
        throw new Error(`figma URL must start with /file/ or /design/, got /${kind ?? ""}`);
    }
    const fileKey = parts[1];
    if (!fileKey) {
        throw new Error("figma URL is missing a file key");
    }
    const rawNodeId = parsed.searchParams.get("node-id");
    const nodeId = rawNodeId !== null ? normalizeNodeId(rawNodeId) : null;
    return { fileKey, nodeId };
}
export function normalizeNodeId(raw) {
    // Figma URLs use `-` but the REST API expects `:`. Double-dashes (`12--345`)
    // stay as-is: they occur in copy-and-paste edge cases.
    return raw.replace(/-/g, ":");
}
export async function fetchDesign(client, input) {
    const { fileKey, nodeId } = resolveTarget(input);
    if (!nodeId) {
        throw new Error("fetchDesign requires a node id (either nodeId, or a URL with ?node-id=).");
    }
    const raw = (await client.getNodes(fileKey, [nodeId]));
    const nodeEnvelope = raw.nodes?.[nodeId];
    if (!nodeEnvelope || !nodeEnvelope.document) {
        const hint = nodeEnvelope?.err ? ` (${nodeEnvelope.err})` : "";
        throw new Error(`figma returned no document for node ${nodeId}${hint}`);
    }
    const doc = nodeEnvelope.document;
    const frames = flattenFrames(doc, 0);
    return {
        fileKey,
        nodeId,
        name: doc.name ?? "",
        type: doc.type ?? "",
        frames,
        fetchedAt: new Date().toISOString(),
    };
}
/** Breadth-first flatten so shallow frames come first — easier to scan. */
export function flattenFrames(root, startDepth) {
    const out = [];
    const queue = [{ node: root, depth: startDepth }];
    while (queue.length > 0) {
        const { node, depth } = queue.shift();
        const children = node.children ?? [];
        out.push({
            id: node.id,
            name: node.name ?? "",
            type: node.type ?? "",
            width: node.absoluteBoundingBox?.width ?? null,
            height: node.absoluteBoundingBox?.height ?? null,
            childCount: children.length,
            depth,
        });
        for (const child of children) {
            queue.push({ node: child, depth: depth + 1 });
        }
    }
    return out;
}
function resolveTarget(input) {
    if (input.url) {
        const parsed = parseFigmaUrl(input.url);
        return {
            fileKey: parsed.fileKey,
            nodeId: input.nodeId ?? parsed.nodeId,
        };
    }
    if (input.fileKey) {
        return {
            fileKey: input.fileKey,
            nodeId: input.nodeId ? normalizeNodeId(input.nodeId) : null,
        };
    }
    throw new Error("fetchDesign requires either a url or a fileKey");
}
//# sourceMappingURL=frames.js.map