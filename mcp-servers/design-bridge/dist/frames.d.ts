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
export declare function parseFigmaUrl(url: string): FigmaLink;
export declare function normalizeNodeId(raw: string): string;
export declare function fetchDesign(client: FigmaClient, input: FetchDesignInput): Promise<FetchDesignResult>;
export interface FigmaNode {
    readonly id: string;
    readonly name?: string;
    readonly type?: string;
    readonly children?: readonly FigmaNode[];
    readonly absoluteBoundingBox?: {
        readonly width?: number;
        readonly height?: number;
    };
    readonly [key: string]: unknown;
}
/** Breadth-first flatten so shallow frames come first — easier to scan. */
export declare function flattenFrames(root: FigmaNode, startDepth: number): FlatFrame[];
