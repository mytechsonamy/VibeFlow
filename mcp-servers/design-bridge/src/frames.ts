import { FigmaClient } from "./client.js";

/**
 * Frame discovery + flattening.
 *
 * Figma links look like:
 *   https://www.figma.com/file/<FILE_KEY>/<title>?node-id=<NODE_ID>
 *   https://www.figma.com/design/<FILE_KEY>/<title>?node-id=<NODE_ID>
 *
 * The URL parser accepts either shape and returns the pair
 * (fileKey, nodeId). Node ids in URLs use `-` as the separator (e.g.
 * `12-345`); Figma's REST API expects `:` (e.g. `12:345`). We normalize here
 * so callers don't have to remember which form they have.
 */

export interface FigmaLink {
  readonly fileKey: string;
  readonly nodeId: string | null;
}

export interface FlatFrame {
  readonly id: string;
  readonly name: string;
  readonly type: string;
  readonly width: number | null;
  readonly height: number | null;
  readonly childCount: number;
  readonly depth: number;
}

export interface FetchDesignInput {
  readonly url?: string;
  readonly fileKey?: string;
  readonly nodeId?: string;
}

export interface FetchDesignResult {
  readonly fileKey: string;
  readonly nodeId: string;
  readonly name: string;
  readonly type: string;
  readonly frames: readonly FlatFrame[];
  readonly fetchedAt: string;
}

export function parseFigmaUrl(url: string): FigmaLink {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error(`not a valid URL: ${url}`);
  }
  if (!/figma\.com$/.test(parsed.hostname) && parsed.hostname !== "figma.com") {
    throw new Error(`not a figma.com URL: ${parsed.hostname}`);
  }
  // Path: /file/<KEY>/<title> or /design/<KEY>/<title>
  const parts = parsed.pathname.split("/").filter((p) => p !== "");
  const kind = parts[0];
  if (kind !== "file" && kind !== "design") {
    throw new Error(
      `figma URL must start with /file/ or /design/, got /${kind ?? ""}`,
    );
  }
  const fileKey = parts[1];
  if (!fileKey) {
    throw new Error("figma URL is missing a file key");
  }
  const rawNodeId = parsed.searchParams.get("node-id");
  const nodeId = rawNodeId !== null ? normalizeNodeId(rawNodeId) : null;
  return { fileKey, nodeId };
}

export function normalizeNodeId(raw: string): string {
  // Figma URLs use `-` but the REST API expects `:`. Double-dashes (`12--345`)
  // stay as-is: they occur in copy-and-paste edge cases.
  return raw.replace(/-/g, ":");
}

export async function fetchDesign(
  client: FigmaClient,
  input: FetchDesignInput,
): Promise<FetchDesignResult> {
  const { fileKey, nodeId } = resolveTarget(input);
  if (!nodeId) {
    throw new Error(
      "fetchDesign requires a node id (either nodeId, or a URL with ?node-id=).",
    );
  }

  const raw = (await client.getNodes(fileKey, [nodeId])) as {
    nodes?: Record<
      string,
      { document?: FigmaNode; name?: string; err?: string }
    >;
  };
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

export interface FigmaNode {
  readonly id: string;
  readonly name?: string;
  readonly type?: string;
  readonly children?: readonly FigmaNode[];
  readonly absoluteBoundingBox?: {
    readonly width?: number;
    readonly height?: number;
  };
  // Other fields (fills, style, etc.) live here too but are consumed by
  // tokens.ts, not this module.
  readonly [key: string]: unknown;
}

/** Breadth-first flatten so shallow frames come first — easier to scan. */
export function flattenFrames(root: FigmaNode, startDepth: number): FlatFrame[] {
  const out: FlatFrame[] = [];
  type Entry = { node: FigmaNode; depth: number };
  const queue: Entry[] = [{ node: root, depth: startDepth }];
  while (queue.length > 0) {
    const { node, depth } = queue.shift()!;
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

function resolveTarget(input: FetchDesignInput): {
  fileKey: string;
  nodeId: string | null;
} {
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
