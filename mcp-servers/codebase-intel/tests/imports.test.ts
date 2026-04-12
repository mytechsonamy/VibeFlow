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
