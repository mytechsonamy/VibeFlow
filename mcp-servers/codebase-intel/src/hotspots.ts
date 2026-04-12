import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Git-churn-based hotspot analysis: files that change often and accumulate
 * lots of edits are riskier to modify. We rank by `commits × total lines
 * changed` over a configurable window (default: last 180 days).
 *
 * Rationale: this is a proxy for "places where regressions happen" — a file
 * that has been touched 40 times in 6 months and gained 1200 lines is a
 * different risk profile than a file touched twice. Downstream skills
 * (test-strategy-planner, arch-guardrails) can use this list to prioritize.
 *
 * Pure-function version of the algorithm also lives in `rankHotspots` so
 * tests can exercise it without spawning git.
 */

export interface FileChurn {
  readonly path: string;
  readonly commits: number;
  readonly linesAdded: number;
  readonly linesDeleted: number;
  readonly score: number;
}

export interface HotspotOptions {
  readonly root: string;
  readonly sinceDays?: number;
  readonly limit?: number;
}

export interface HotspotResult {
  readonly root: string;
  readonly sinceDays: number;
  readonly files: readonly FileChurn[];
}

export function findHotspots(opts: HotspotOptions): HotspotResult {
  const root = path.resolve(opts.root);
  const sinceDays = opts.sinceDays ?? 180;
  const limit = opts.limit ?? 20;

  if (!isGitRepo(root)) {
    return { root, sinceDays, files: [] };
  }

  const raw = gitLogNumstat(root, sinceDays);
  const churn = parseNumstat(raw);
  const ranked = rankHotspots(churn, limit);
  return { root, sinceDays, files: ranked };
}

export function isGitRepo(root: string): boolean {
  try {
    execFileSync("git", ["-C", root, "rev-parse", "--git-dir"], {
      stdio: ["ignore", "ignore", "ignore"],
    });
    return true;
  } catch {
    return false;
  }
}

function gitLogNumstat(root: string, sinceDays: number): string {
  try {
    const out = execFileSync(
      "git",
      [
        "-C",
        root,
        "log",
        `--since=${sinceDays}.days.ago`,
        "--numstat",
        "--format=",
        "--no-merges",
      ],
      { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
    );
    return out;
  } catch {
    return "";
  }
}

/**
 * Parse `git log --numstat --format=` output. Each line is
 * `<added>\t<deleted>\t<path>`. Binary files show `-\t-\t<path>` and are
 * aggregated but contribute 0 line changes.
 */
export function parseNumstat(raw: string): Map<string, FileChurn> {
  const byPath = new Map<string, { commits: number; added: number; deleted: number }>();
  for (const rawLine of raw.split("\n")) {
    const line = rawLine.trim();
    if (line === "") continue;
    const parts = line.split("\t");
    if (parts.length < 3) continue;
    const added = parts[0] === "-" ? 0 : parseInt(parts[0]!, 10);
    const deleted = parts[1] === "-" ? 0 : parseInt(parts[1]!, 10);
    const filePath = parts.slice(2).join("\t");
    if (!Number.isFinite(added) || !Number.isFinite(deleted) || filePath === "") continue;
    const existing = byPath.get(filePath) ?? { commits: 0, added: 0, deleted: 0 };
    existing.commits += 1;
    existing.added += added;
    existing.deleted += deleted;
    byPath.set(filePath, existing);
  }
  const out = new Map<string, FileChurn>();
  for (const [p, v] of byPath) {
    out.set(p, {
      path: p,
      commits: v.commits,
      linesAdded: v.added,
      linesDeleted: v.deleted,
      score: v.commits * (v.added + v.deleted),
    });
  }
  return out;
}

export function rankHotspots(
  churn: ReadonlyMap<string, FileChurn>,
  limit: number,
): FileChurn[] {
  return [...churn.values()]
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      if (b.commits !== a.commits) return b.commits - a.commits;
      return a.path.localeCompare(b.path);
    })
    .slice(0, limit);
}

/** Verify a directory truly contains a git repo (tests need this). */
export function hasGitDir(root: string): boolean {
  return fs.existsSync(path.join(root, ".git"));
}
