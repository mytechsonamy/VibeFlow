import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { compareImages, parsePngDimensions, readImage } from "../src/compare.js";

/**
 * Build a minimal valid PNG buffer containing just a signature + IHDR chunk.
 * That's enough for `parsePngDimensions` to succeed. We don't care about
 * IDAT/IEND for this test.
 */
function pngStub(width: number, height: number, filler = 0): Buffer {
  const sig = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const chunkLength = Buffer.alloc(4);
  chunkLength.writeUInt32BE(13, 0);
  const chunkType = Buffer.from("IHDR", "ascii");
  const payload = Buffer.alloc(13);
  payload.writeUInt32BE(width, 0);
  payload.writeUInt32BE(height, 4);
  payload[8] = 8; // bit depth
  payload[9] = 2; // color type
  // Compression / filter / interlace left as 0.
  const crc = Buffer.from([0, 0, 0, 0]);
  const filler_bytes = Buffer.alloc(filler > 0 ? filler : 0);
  return Buffer.concat([sig, chunkLength, chunkType, payload, crc, filler_bytes]);
}

describe("parsePngDimensions", () => {
  it("extracts width/height from the IHDR chunk", () => {
    const buf = pngStub(640, 480);
    expect(parsePngDimensions(buf)).toEqual({ width: 640, height: 480 });
  });

  it("returns null for non-PNG input", () => {
    expect(parsePngDimensions(Buffer.from("hello world"))).toBeNull();
  });

  it("returns null for truncated input", () => {
    expect(parsePngDimensions(Buffer.alloc(10))).toBeNull();
  });
});

describe("compareImages", () => {
  let dir: string;
  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "db-compare-"));
  });
  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("returns identical when SHA matches", () => {
    const p = path.join(dir, "a.png");
    fs.writeFileSync(p, pngStub(100, 100));
    const q = path.join(dir, "b.png");
    fs.writeFileSync(q, pngStub(100, 100));
    const r = compareImages(p, q);
    expect(r.verdict).toBe("identical");
  });

  it("returns same-dimensions when bytes differ but width×height match", () => {
    const p = path.join(dir, "a.png");
    fs.writeFileSync(p, pngStub(100, 100, 0));
    const q = path.join(dir, "b.png");
    fs.writeFileSync(q, pngStub(100, 100, 16));
    const r = compareImages(p, q);
    expect(r.verdict).toBe("same-dimensions");
    expect(r.notes.some((n) => /pixel-level diff deferred/.test(n))).toBe(true);
  });

  it("returns size-mismatch when dimensions differ", () => {
    const p = path.join(dir, "a.png");
    fs.writeFileSync(p, pngStub(100, 100));
    const q = path.join(dir, "b.png");
    fs.writeFileSync(q, pngStub(200, 100));
    const r = compareImages(p, q);
    expect(r.verdict).toBe("size-mismatch");
  });

  it("reports unknown for non-PNG inputs", () => {
    const p = path.join(dir, "a.bin");
    fs.writeFileSync(p, Buffer.from("binary-file-a"));
    const q = path.join(dir, "b.bin");
    fs.writeFileSync(q, Buffer.from("binary-file-b"));
    const r = compareImages(p, q);
    expect(r.verdict).toBe("unknown");
    expect(r.notes.some((n) => /not a PNG/.test(n))).toBe(true);
  });

  it("computes sizeDeltaBytes and sizeDeltaRatio", () => {
    const p = path.join(dir, "a.png");
    fs.writeFileSync(p, pngStub(100, 100, 0));
    const q = path.join(dir, "b.png");
    fs.writeFileSync(q, pngStub(100, 100, 20));
    const r = compareImages(p, q);
    expect(r.sizeDeltaBytes).toBe(20);
    expect(r.sizeDeltaRatio).toBeGreaterThan(0);
  });

  it("readImage handles arbitrary binary files without throwing", () => {
    const p = path.join(dir, "bin.dat");
    fs.writeFileSync(p, Buffer.from([1, 2, 3]));
    const info = readImage(p);
    expect(info.format).toBe("unknown");
    expect(info.bytes).toBe(3);
  });
});
