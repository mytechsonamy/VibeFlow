import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { scanRepo } from "../src/scanner.js";

function writeJson(p: string, obj: unknown): void {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, JSON.stringify(obj, null, 2));
}

describe("scanRepo", () => {
  let dir: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ci-scanner-"));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  it("detects javascript from a bare package.json", async () => {
    writeJson(path.join(dir, "package.json"), { name: "x", version: "1.0.0" });
    const r = await scanRepo(dir);
    expect(r.languages.map((l) => l.name)).toContain("javascript");
    expect(r.languages[0]!.evidence).toContain("package.json");
  });

  it("promotes to typescript when tsconfig.json is present and drops javascript", async () => {
    writeJson(path.join(dir, "package.json"), { name: "x", version: "1.0.0" });
    fs.writeFileSync(path.join(dir, "tsconfig.json"), "{}");
    const r = await scanRepo(dir);
    const names = r.languages.map((l) => l.name);
    expect(names).toContain("typescript");
    expect(names).not.toContain("javascript");
    const ts = r.languages.find((l) => l.name === "typescript")!;
    expect(ts.confidence).toBeGreaterThanOrEqual(0.9);
    expect(r.buildTools.find((b) => b.name === "tsc")).toBeDefined();
  });

  it("detects fastify framework from dependencies", async () => {
    writeJson(path.join(dir, "package.json"), {
      name: "x",
      dependencies: { fastify: "^4.0.0" },
    });
    const r = await scanRepo(dir);
    expect(r.frameworks.map((f) => f.name)).toContain("fastify");
  });

  it("detects vitest via devDependencies and upgrades confidence on config file", async () => {
    writeJson(path.join(dir, "package.json"), {
      name: "x",
      devDependencies: { vitest: "^2.0.0" },
    });
    fs.writeFileSync(path.join(dir, "vitest.config.ts"), "export default {};");
    const r = await scanRepo(dir);
    const vitest = r.testRunners.find((t) => t.name === "vitest")!;
    expect(vitest).toBeDefined();
    expect(vitest.confidence).toBeGreaterThanOrEqual(0.95);
    expect(vitest.evidence).toContain("vitest.config.ts");
  });

  it("detects go via go.mod", async () => {
    fs.writeFileSync(path.join(dir, "go.mod"), "module example\n\ngo 1.21\n");
    const r = await scanRepo(dir);
    expect(r.languages.map((l) => l.name)).toEqual(["go"]);
  });

  it("detects rust via Cargo.toml", async () => {
    fs.writeFileSync(path.join(dir, "Cargo.toml"), '[package]\nname = "x"\n');
    const r = await scanRepo(dir);
    expect(r.languages.map((l) => l.name)).toEqual(["rust"]);
  });

  it("falls back to directory heuristic when no manifest is present", async () => {
    fs.mkdirSync(path.join(dir, "src"));
    fs.writeFileSync(path.join(dir, "src", "a.ts"), "export const x = 1;");
    fs.writeFileSync(path.join(dir, "src", "b.ts"), "export const y = 2;");
    const r = await scanRepo(dir);
    const ts = r.languages.find((l) => l.name === "typescript");
    expect(ts).toBeDefined();
    expect(ts!.confidence).toBeLessThanOrEqual(0.5);
  });

  it("throws on a non-existent root", async () => {
    await expect(scanRepo(path.join(dir, "missing"))).rejects.toThrow(/does not exist/);
  });

  it("safely handles corrupt package.json (no crash, no frameworks)", async () => {
    fs.writeFileSync(path.join(dir, "package.json"), "{ not json");
    const r = await scanRepo(dir);
    // Still detects javascript from the manifest file existing.
    expect(r.languages.map((l) => l.name)).toContain("javascript");
    expect(r.frameworks).toEqual([]);
  });
});
