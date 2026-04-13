import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  buildImportGraph,
  extractSpecifiers,
  findCycles,
} from "../src/imports.js";

function write(file: string, content: string): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

describe("extractSpecifiers", () => {
  it("handles import, export-from, require, and dynamic import", () => {
    const src = `
      import a from "./a";
      import { b } from './b';
      import "side-effect";
      export { c } from "./c";
      const d = require('./d');
      const e = await import("./e");
      // import "./commented-out";
      /* import "./block-commented"; */
    `;
    const specs = extractSpecifiers(src);
    expect(specs.sort()).toEqual([
      "./a",
      "./b",
      "./c",
      "./d",
      "./e",
      "side-effect",
    ]);
  });

  it("ignores template literal imports (heuristic limitation)", () => {
    const src = "const x = await import(`./${name}`);";
    expect(extractSpecifiers(src)).toEqual([]);
  });
});

describe("buildImportGraph", () => {
  let dir: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ci-imports-"));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("resolves relative imports to real files under the root", () => {
    write(path.join(dir, "src/a.ts"), 'import { b } from "./b";\nexport const a = 1;');
    write(path.join(dir, "src/b.ts"), 'export const b = 2;');

    const g = buildImportGraph(dir);
    expect(g.files.sort()).toEqual(["src/a.ts", "src/b.ts"]);
    expect(g.edges).toEqual([{ from: "src/a.ts", to: "src/b.ts" }]);
    expect(g.externalImports).toEqual([]);
    expect(g.unresolved).toEqual([]);
  });

  it("resolves imports pointing at a directory with index.ts", () => {
    write(path.join(dir, "src/a.ts"), 'import { b } from "./lib";');
    write(path.join(dir, "src/lib/index.ts"), 'export const b = 1;');
    const g = buildImportGraph(dir);
    expect(g.edges).toEqual([{ from: "src/a.ts", to: "src/lib/index.ts" }]);
  });

  it("records external package imports separately", () => {
    write(path.join(dir, "src/a.ts"), 'import fastify from "fastify";\nimport { z } from "zod";');
    const g = buildImportGraph(dir);
    expect(g.externalImports.map((e) => e.specifier).sort()).toEqual([
      "fastify",
      "zod",
    ]);
    expect(g.edges).toEqual([]);
  });

  it("marks dangling relative imports as unresolved", () => {
    write(path.join(dir, "src/a.ts"), 'import { x } from "./does-not-exist";');
    const g = buildImportGraph(dir);
    expect(g.unresolved.length).toBe(1);
    expect(g.unresolved[0]!.specifier).toBe("./does-not-exist");
  });

  it("skips dist, build, and node_modules when collecting files", () => {
    write(path.join(dir, "src/a.ts"), 'export const a = 1;');
    write(path.join(dir, "node_modules/pkg/index.js"), "export {};");
    write(path.join(dir, "dist/bundle.js"), "export {};");
    write(path.join(dir, "build/out.js"), "export {};");
    const g = buildImportGraph(dir);
    expect(g.files).toEqual(["src/a.ts"]);
  });
});

describe("findCycles", () => {
  let dir: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ci-cycles-"));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("returns no cycles on an acyclic graph", () => {
    write(path.join(dir, "a.ts"), 'import "./b";');
    write(path.join(dir, "b.ts"), 'import "./c";');
    write(path.join(dir, "c.ts"), 'export const c = 1;');
    const g = buildImportGraph(dir);
    expect(findCycles(g)).toEqual([]);
  });

  it("detects a 2-node cycle", () => {
    write(path.join(dir, "a.ts"), 'import "./b";');
    write(path.join(dir, "b.ts"), 'import "./a";');
    const g = buildImportGraph(dir);
    const cycles = findCycles(g);
    expect(cycles.length).toBe(1);
    expect(cycles[0]!.sort()).toEqual(["a.ts", "b.ts"]);
  });

  it("detects a 3-node cycle", () => {
    write(path.join(dir, "a.ts"), 'import "./b";');
    write(path.join(dir, "b.ts"), 'import "./c";');
    write(path.join(dir, "c.ts"), 'import "./a";');
    const g = buildImportGraph(dir);
    const cycles = findCycles(g);
    expect(cycles.length).toBe(1);
    expect(cycles[0]!.length).toBe(3);
  });
});

// ---------------------------------------------------------------------------
// Large-input scaling (S4-08).
// Synthesizes a 200-file project with a moderate fan-in and runs
// buildImportGraph + findCycles end-to-end. Catches accidental N²
// loops (e.g. quadratic resolution rescans on every import).
//
// The scenario is intentionally larger than any project in the repo's
// own test fixtures so a regression that adds quadratic work shows up
// before it lands in production.
// ---------------------------------------------------------------------------

describe("buildImportGraph — large-input scaling", () => {
  let dir: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ci-large-"));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("handles a 200-file project under 5 seconds", () => {
    const N = 200;
    // Each file imports the next two — a chain plus one fan-out edge.
    // This is roughly the shape of a real medium-sized service module.
    for (let i = 0; i < N; i++) {
      const next = (i + 1) % N;
      const next2 = (i + 2) % N;
      write(
        path.join(dir, `mod-${i}.ts`),
        `import "./mod-${next}";\nimport "./mod-${next2}";\nexport const m${i} = ${i};\n`,
      );
    }

    const start = Date.now();
    const g = buildImportGraph(dir);
    const elapsed = Date.now() - start;

    expect(g.files.length).toBe(N);
    // Chain (N) + fan-out (N) = 2N edges. The modulo wrap creates a
    // cycle so the total is exactly 2*N for this layout.
    expect(g.edges.length).toBe(2 * N);
    expect(g.unresolved).toEqual([]);
    expect(elapsed).toBeLessThan(5000);
  });

  it("findCycles terminates on a 200-file dense graph under 2 seconds", () => {
    const N = 200;
    for (let i = 0; i < N; i++) {
      const next = (i + 1) % N;
      write(
        path.join(dir, `mod-${i}.ts`),
        `import "./mod-${next}";\nexport const m${i} = ${i};\n`,
      );
    }

    const g = buildImportGraph(dir);
    const start = Date.now();
    const cycles = findCycles(g);
    const elapsed = Date.now() - start;

    // The chain wraps around so every node participates in the same
    // single cycle of length N.
    expect(cycles.length).toBe(1);
    expect(cycles[0]!.length).toBe(N);
    expect(elapsed).toBeLessThan(2000);
  });
});
