import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Lightweight tech-debt scan: grep the source tree for debt markers and
 * report findings in the standard explainability shape. This is deliberately
 * simple — heavier analyses (dead code, cyclomatic complexity, outdated
 * dependency versions) are separate tickets.
 *
 * Markers include the usual suspects plus "XXX" and "@deprecated", which
 * surface API sunsets that a normal TODO grep misses.
 */

export interface DebtFinding {
  readonly finding: string;
  readonly why: string;
  readonly impact: "blocks merge" | "soft warning" | "informational";
  readonly confidence: number;
  readonly file: string;
  readonly line: number;
  readonly marker: string;
}

export interface DebtScanOptions {
  readonly root: string;
  readonly limit?: number;
}

export interface DebtScanResult {
  readonly root: string;
  readonly scannedAt: string;
  readonly findings: readonly DebtFinding[];
  readonly totals: ReadonlyMap<string, number>;
}

const DEFAULT_LIMIT = 500;
const SCANNABLE_EXTS = new Set([
  ".ts",
  ".tsx",
  ".js",
  ".jsx",
  ".mjs",
  ".cjs",
  ".mts",
  ".cts",
  ".py",
  ".go",
  ".rs",
  ".java",
  ".kt",
  ".rb",
  ".php",
  ".swift",
  ".cs",
]);

interface Marker {
  readonly name: string;
  readonly pattern: RegExp;
  readonly impact: DebtFinding["impact"];
  readonly confidence: number;
}

const MARKERS: readonly Marker[] = [
  {
    name: "TODO",
    pattern: /\b(TODO)\b[:\s]?(.*)/,
    impact: "informational",
    confidence: 0.9,
  },
  {
    name: "FIXME",
    pattern: /\b(FIXME)\b[:\s]?(.*)/,
    impact: "soft warning",
    confidence: 0.95,
  },
  {
    name: "HACK",
    pattern: /\b(HACK)\b[:\s]?(.*)/,
    impact: "soft warning",
    confidence: 0.95,
  },
  {
    name: "XXX",
    pattern: /\b(XXX)\b[:\s]?(.*)/,
    impact: "soft warning",
    confidence: 0.85,
  },
  {
    name: "@deprecated",
    pattern: /@deprecated\b[:\s]?(.*)/,
    impact: "informational",
    confidence: 0.95,
  },
];

export function scanDebt(opts: DebtScanOptions): DebtScanResult {
  const root = path.resolve(opts.root);
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
    throw new Error(`debtscan: root does not exist or is not a directory: ${root}`);
  }
  const limit = opts.limit ?? DEFAULT_LIMIT;
  const files = collectFiles(root);
  const findings: DebtFinding[] = [];
  const totals = new Map<string, number>();

  outer: for (const file of files) {
    const src = safeRead(file);
    if (src === null) continue;
    const lines = src.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]!;
      for (const marker of MARKERS) {
        const m = line.match(marker.pattern);
        if (!m) continue;
        const msg = (m[2] ?? m[1] ?? "").trim() || "(no detail)";
        findings.push({
          finding: `${marker.name}: ${truncate(msg, 120)}`,
          why: `debt marker detected at ${path.relative(root, file)}:${i + 1}`,
          impact: marker.impact,
          confidence: marker.confidence,
          file: path.relative(root, file),
          line: i + 1,
          marker: marker.name,
        });
        totals.set(marker.name, (totals.get(marker.name) ?? 0) + 1);
        if (findings.length >= limit) break outer;
        break; // one marker per line is enough
      }
    }
  }

  return {
    root,
    scannedAt: new Date().toISOString(),
    findings,
    totals,
  };
}

function collectFiles(root: string): string[] {
  const out: string[] = [];
  const stack: string[] = [root];
  while (stack.length > 0) {
    const current = stack.pop()!;
    let entries: fs.Dirent[] = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      if (
        e.name.startsWith(".") ||
        e.name === "node_modules" ||
        e.name === "dist" ||
        e.name === "build" ||
        e.name === "vendor"
      ) {
        continue;
      }
      const full = path.join(current, e.name);
      if (e.isDirectory()) {
        stack.push(full);
      } else if (SCANNABLE_EXTS.has(path.extname(e.name).toLowerCase())) {
        out.push(full);
      }
    }
  }
  return out;
}

function safeRead(file: string): string | null {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return null;
  }
}

function truncate(s: string, max: number): string {
  return s.length <= max ? s : s.slice(0, max - 1) + "…";
}
