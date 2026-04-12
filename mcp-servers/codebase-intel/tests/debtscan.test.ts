import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { scanDebt } from "../src/debtscan.js";

function write(file: string, content: string): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
}

describe("scanDebt", () => {
  let dir: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ci-debt-"));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("finds TODO, FIXME, HACK, XXX, and @deprecated markers", () => {
    write(
      path.join(dir, "src/a.ts"),
      `
// TODO: refactor this
function f() {}
// FIXME: bug in edge case
// HACK: quick workaround
// XXX: assumes foo
/** @deprecated use newThing */
`,
    );
    const r = scanDebt({ root: dir });
    const markers = r.findings.map((f) => f.marker).sort();
    expect(markers).toEqual([
      "@deprecated",
      "FIXME",
      "HACK",
      "TODO",
      "XXX",
    ]);
  });

  it("reports correct line numbers", () => {
    write(
      path.join(dir, "src/a.ts"),
      "const x = 1;\nconst y = 2;\n// TODO: fix\n",
    );
    const r = scanDebt({ root: dir });
    expect(r.findings.length).toBe(1);
    expect(r.findings[0]!.line).toBe(3);
    expect(r.findings[0]!.file).toBe("src/a.ts");
  });

  it("assigns FIXME the soft-warning impact and TODO informational", () => {
    write(path.join(dir, "src/a.ts"), "// TODO: one\n// FIXME: two\n");
    const r = scanDebt({ root: dir });
    const todo = r.findings.find((f) => f.marker === "TODO")!;
    const fixme = r.findings.find((f) => f.marker === "FIXME")!;
    expect(todo.impact).toBe("informational");
    expect(fixme.impact).toBe("soft warning");
  });

  it("aggregates totals per marker", () => {
    write(path.join(dir, "src/a.ts"), "// TODO: a\n");
    write(path.join(dir, "src/b.ts"), "// TODO: b\n// FIXME: c\n");
    const r = scanDebt({ root: dir });
    expect(r.totals.get("TODO")).toBe(2);
    expect(r.totals.get("FIXME")).toBe(1);
  });

  it("respects the limit", () => {
    const body = new Array(20).fill("// TODO: x").join("\n") + "\n";
    write(path.join(dir, "src/a.ts"), body);
    const r = scanDebt({ root: dir, limit: 5 });
    expect(r.findings.length).toBe(5);
  });

  it("skips node_modules, dist, build, vendor", () => {
    write(path.join(dir, "node_modules/x/a.ts"), "// TODO: skip me\n");
    write(path.join(dir, "dist/x.ts"), "// TODO: skip me\n");
    write(path.join(dir, "build/x.ts"), "// TODO: skip me\n");
    write(path.join(dir, "vendor/x.ts"), "// TODO: skip me\n");
    write(path.join(dir, "src/x.ts"), "// TODO: keep me\n");
    const r = scanDebt({ root: dir });
    expect(r.findings.length).toBe(1);
    expect(r.findings[0]!.file).toBe("src/x.ts");
  });

  it("throws on a non-existent root", () => {
    expect(() => scanDebt({ root: path.join(dir, "nope") })).toThrow(/does not exist/);
  });
});
