/**
 * Minimal, dependency-free image comparison.
 *
 * Full perceptual pixel diff (pixelmatch / SSIM) needs PNG decoding and
 * belongs in Sprint 3 alongside the visual-ai-analyzer skill. For S2-02 we
 * surface the actionable signals that don't need a decoder:
 *
 *   - identical bytes (SHA-256)
 *   - byte-size delta (and ratio)
 *   - PNG dimensions (parsed from the IHDR header — 8-byte PNG signature
 *     followed by a 4-byte length, "IHDR" type, then width/height as BE u32)
 *
 * The tool result carries a `verdict` string: `identical`, `same-dimensions`,
 * `size-mismatch`, or `unknown`. Skills and humans can decide what to do
 * with it — we refuse to invent a similarity score we can't defend.
 */
export interface ImageInfo {
    readonly path: string;
    readonly bytes: number;
    readonly sha256: string;
    readonly width: number | null;
    readonly height: number | null;
    readonly format: "png" | "unknown";
}
export interface CompareResult {
    readonly left: ImageInfo;
    readonly right: ImageInfo;
    readonly verdict: "identical" | "same-dimensions" | "size-mismatch" | "unknown";
    readonly sizeDeltaBytes: number;
    readonly sizeDeltaRatio: number;
    readonly notes: readonly string[];
}
export declare function compareImages(leftPath: string, rightPath: string): CompareResult;
export declare function readImage(p: string): ImageInfo;
/**
 * PNG structure:
 *   [8-byte signature: 89 50 4E 47 0D 0A 1A 0A]
 *   [4-byte length] [4-byte type "IHDR"] [13-byte IHDR payload] [4-byte CRC]
 *   IHDR payload: width(4) | height(4) | bit depth(1) | color type(1) | ...
 *
 * That gets us width/height with no decoder. IDAT/IEND are irrelevant here.
 */
export declare function parsePngDimensions(buf: Buffer): {
    width: number;
    height: number;
} | null;
