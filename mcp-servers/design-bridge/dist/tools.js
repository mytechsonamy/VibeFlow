import { z } from "zod";
import { FigmaClient, FigmaClientError, FigmaConfigError, } from "./client.js";
import { fetchDesign } from "./frames.js";
import { extractTokens } from "./tokens.js";
import { generateStyles } from "./styles.js";
import { compareImages } from "./compare.js";
const FetchDesignInput = z
    .object({
    url: z.string().url().optional(),
    fileKey: z.string().min(1).optional(),
    nodeId: z.string().min(1).optional(),
})
    .refine((v) => v.url !== undefined || v.fileKey !== undefined, {
    message: "either url or fileKey is required",
});
const ExtractTokensInput = z
    .object({
    url: z.string().url().optional(),
    fileKey: z.string().min(1).optional(),
    nodeId: z.string().min(1).optional(),
})
    .refine((v) => v.url !== undefined || v.fileKey !== undefined, {
    message: "either url or fileKey is required",
});
const GenerateStylesInput = z
    .object({
    url: z.string().url().optional(),
    fileKey: z.string().min(1).optional(),
    nodeId: z.string().min(1).optional(),
})
    .refine((v) => v.url !== undefined || v.fileKey !== undefined, {
    message: "either url or fileKey is required",
});
const CompareImplInput = z.object({
    leftPath: z.string().min(1),
    rightPath: z.string().min(1),
});
export function buildTools(opts = {}) {
    const getClient = () => {
        try {
            return new FigmaClient({
                token: opts.token,
                baseUrl: opts.baseUrl,
                fetchImpl: opts.fetchImpl,
            });
        }
        catch (err) {
            if (err instanceof FigmaConfigError)
                throw err;
            throw err;
        }
    };
    return [
        {
            name: "db_fetch_design",
            description: "Fetch a Figma frame by URL or (fileKey, nodeId) and return a " +
                "flattened list of child frames with depth + dimensions.",
            inputSchema: {
                type: "object",
                properties: {
                    url: { type: "string" },
                    fileKey: { type: "string", minLength: 1 },
                    nodeId: { type: "string", minLength: 1 },
                },
                additionalProperties: false,
            },
            handler: async (raw) => {
                const args = FetchDesignInput.parse(raw);
                const client = getClient();
                return fetchDesign(client, args);
            },
        },
        {
            name: "db_extract_tokens",
            description: "Walk a Figma frame and return color, typography, and spacing " +
                "tokens with source node IDs as evidence. Every token is deduped.",
            inputSchema: {
                type: "object",
                properties: {
                    url: { type: "string" },
                    fileKey: { type: "string", minLength: 1 },
                    nodeId: { type: "string", minLength: 1 },
                },
                additionalProperties: false,
            },
            handler: async (raw) => {
                const args = ExtractTokensInput.parse(raw);
                const client = getClient();
                const node = await fetchRawNode(client, args);
                return extractTokens(node);
            },
        },
        {
            name: "db_generate_styles",
            description: "Produce CSS custom properties and a Tailwind config snippet from " +
                "the tokens extracted from a Figma frame.",
            inputSchema: {
                type: "object",
                properties: {
                    url: { type: "string" },
                    fileKey: { type: "string", minLength: 1 },
                    nodeId: { type: "string", minLength: 1 },
                },
                additionalProperties: false,
            },
            handler: async (raw) => {
                const args = GenerateStylesInput.parse(raw);
                const client = getClient();
                const node = await fetchRawNode(client, args);
                const tokens = extractTokens(node);
                return { tokens, ...generateStyles(tokens) };
            },
        },
        {
            name: "db_compare_impl",
            description: "Compare two PNG images (screenshot vs reference). Returns " +
                "identical | same-dimensions | size-mismatch | unknown. Full " +
                "perceptual diff is deferred to the visual-ai-analyzer skill.",
            inputSchema: {
                type: "object",
                properties: {
                    leftPath: { type: "string", minLength: 1 },
                    rightPath: { type: "string", minLength: 1 },
                },
                required: ["leftPath", "rightPath"],
                additionalProperties: false,
            },
            handler: async (raw) => {
                const args = CompareImplInput.parse(raw);
                return compareImages(args.leftPath, args.rightPath);
            },
        },
    ];
}
/**
 * Shared helper for tools that want the raw Figma node (not just the flat
 * frame list). We hit the same `/v1/files/.../nodes` endpoint and pull the
 * `document` back out.
 */
async function fetchRawNode(client, input) {
    const design = await fetchDesign(client, input);
    const raw = (await client.getNodes(design.fileKey, [design.nodeId]));
    const doc = raw.nodes?.[design.nodeId]?.document;
    if (!doc) {
        const err = raw.nodes?.[design.nodeId]?.err;
        throw new FigmaClientError(`figma returned no document for node ${design.nodeId}${err ? ` (${err})` : ""}`, { status: 0, path: `/v1/files/${design.fileKey}/nodes` });
    }
    return doc;
}
//# sourceMappingURL=tools.js.map