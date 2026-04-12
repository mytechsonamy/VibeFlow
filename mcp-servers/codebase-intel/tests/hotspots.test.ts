import { describe, expect, it, beforeEach, afterEach } from "vitest";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { execFileSync } from "node:child_process";
import {
  findHotspots,
  parseNumstat,
  rankHotspots,
  isGitRepo,
} from "../src/hotspots.js";

describe("parseNumstat", () => {
  it("parses added/deleted/path rows and accumulates per file", () => {
    const raw = "10\t2\tsrc/a.ts\n3\t1\tsrc/a.ts\n5\t5\tsrc/b.ts\n";
    const churn = parseNumstat(raw);
    const a = churn.get("src/a.ts")!;
    expect(a.commits).toBe(2);
    expect(a.linesAdded).toBe(13);
    expect(a.linesDeleted).toBe(3);
    expect(a.score).toBe(2 * (13 + 3));

    const b = churn.get("src/b.ts")!;
    expect(b.commits).toBe(1);
    expect(b.score).toBe(10);
  });

  it("treats binary rows (-\\t-) as zero-line changes", () => {
    const raw = "-\t-\tasset.png\n";
    const churn = parseNumstat(raw);
    const asset = churn.get("asset.png")!;
    expect(asset.linesAdded).toBe(0);
    expect(asset.linesDeleted).toBe(0);
    expect(asset.score).toBe(0);
    expect(asset.commits).toBe(1);
  });

  it("ignores malformed lines", () => {
    const raw = "garbage\n5\t5\tsrc/ok.ts\n";
    const churn = parseNumstat(raw);
    expect(churn.size).toBe(1);
    expect(churn.get("src/ok.ts")).toBeDefined();
  });
});

describe("rankHotspots", () => {
  it("sorts by score descending, tie-breaks on commits then path", () => {
    const churn = new Map([
      ["a", { path: "a", commits: 2, linesAdded: 5, linesDeleted: 5, score: 20 }],
      ["b", { path: "b", commits: 5, linesAdded: 50, linesDeleted: 50, score: 500 }],
      ["c", { path: "c", commits: 5, linesAdded: 50, linesDeleted: 50, score: 500 }],
    ]);
    const ranked = rankHotspots(churn, 5);
    expect(ranked.map((f) => f.path)).toEqual(["b", "c", "a"]);
  });

  it("respects the limit", () => {
    const churn = new Map([
      ["a", { path: "a", commits: 1, linesAdded: 1, linesDeleted: 0, score: 1 }],
      ["b", { path: "b", commits: 2, linesAdded: 2, linesDeleted: 0, score: 4 }],
      ["c", { path: "c", commits: 3, linesAdded: 3, linesDeleted: 0, score: 9 }],
    ]);
    expect(rankHotspots(churn, 2).map((f) => f.path)).toEqual(["c", "b"]);
  });
});

describe("findHotspots (integration against a real git repo)", () => {
  let dir: string;

  beforeEach(() => {
    dir = fs.mkdtempSync(path.join(os.tmpdir(), "ci-hotspots-"));
  });

  afterEach(() => {
    fs.rmSync(dir, { recursive: true, force: true });
  });

  function git(...args: string[]): void {
    execFileSync("git", ["-C", dir, ...args], { stdio: "ignore" });
  }

  it("returns an empty list for a non-git directory", () => {
    const r = findHotspots({ root: dir });
    expect(r.files).toEqual([]);
    expect(isGitRepo(dir)).toBe(false);
  });

  it("ranks files that churn more often higher than one-touch files", () => {
    git("init", "-q");
    git("config", "user.email", "t@e.com");
    git("config", "user.name", "t");

    fs.writeFileSync(path.join(dir, "hot.ts"), "a\n");
    git("add", "hot.ts");
    git("commit", "-q", "-m", "add hot");

    for (let i = 0; i < 3; i++) {
      fs.appendFileSync(path.join(dir, "hot.ts"), `line ${i}\n`);
      git("add", "hot.ts");
      git("commit", "-q", "-m", `edit hot ${i}`);
    }

    fs.writeFileSync(path.join(dir, "cold.ts"), "a\n");
    git("add", "cold.ts");
    git("commit", "-q", "-m", "add cold");

    const r = findHotspots({ root: dir, limit: 10 });
    expect(r.files.length).toBeGreaterThanOrEqual(2);
    expect(r.files[0]!.path).toBe("hot.ts");
    expect(r.files[0]!.commits).toBeGreaterThan(r.files[1]!.commits);
  });
});
