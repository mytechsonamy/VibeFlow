import * as fs from "node:fs";
import * as crypto from "node:crypto";
export function compareImages(leftPath, rightPath) {
    const left = readImage(leftPath);
    const right = readImage(rightPath);
    const notes = [];
    if (left.format !== "png" || right.format !== "png") {
        notes.push("at least one input is not a PNG; dimension comparison skipped (only byte-level signals remain)");
    }
    let verdict = "unknown";
    if (left.sha256 === right.sha256) {
        verdict = "identical";
    }
    else if (left.width !== null &&
        right.width !== null &&
        left.width === right.width &&
        left.height === right.height) {
        verdict = "same-dimensions";
        notes.push("bytes differ but width × height match — pixel-level diff deferred to Sprint 3 (visual-ai-analyzer)");
    }
    else if (left.width !== null &&
        right.width !== null &&
        (left.width !== right.width || left.height !== right.height)) {
        verdict = "size-mismatch";
    }
    const sizeDeltaBytes = right.bytes - left.bytes;
    const sizeDeltaRatio = left.bytes > 0 ? sizeDeltaBytes / left.bytes : 0;
    return { left, right, verdict, sizeDeltaBytes, sizeDeltaRatio, notes };
}
export function readImage(p) {
    const buf = fs.readFileSync(p);
    const sha256 = crypto.createHash("sha256").update(buf).digest("hex");
    const png = parsePngDimensions(buf);
    return {
        path: p,
        bytes: buf.length,
        sha256,
        width: png?.width ?? null,
        height: png?.height ?? null,
        format: png ? "png" : "unknown",
    };
}
/**
 * PNG structure:
 *   [8-byte signature: 89 50 4E 47 0D 0A 1A 0A]
 *   [4-byte length] [4-byte type "IHDR"] [13-byte IHDR payload] [4-byte CRC]
 *   IHDR payload: width(4) | height(4) | bit depth(1) | color type(1) | ...
 *
 * That gets us width/height with no decoder. IDAT/IEND are irrelevant here.
 */
export function parsePngDimensions(buf) {
    if (buf.length < 24)
        return null;
    const sig = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    for (let i = 0; i < sig.length; i++) {
        if (buf[i] !== sig[i])
            return null;
    }
    // First chunk should be IHDR at offset 8.
    const chunkType = buf.toString("ascii", 12, 16);
    if (chunkType !== "IHDR")
        return null;
    const width = buf.readUInt32BE(16);
    const height = buf.readUInt32BE(20);
    if (!Number.isFinite(width) || !Number.isFinite(height))
        return null;
    return { width, height };
}
//# sourceMappingURL=compare.js.map