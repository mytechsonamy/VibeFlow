import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Regex-based import-graph builder for TypeScript/JavaScript projects.
 *
 * This is deliberately NOT a full parser. ts-morph / babel is heavy and most
 * downstream uses (layering enforcement, cycle detection) only need to know
 * "file A references file B". A false positive on a dynamic `import(expr)`
 * is acceptable — we surface it honestly with lower confidence.
 *
 * The resolver follows the project root + relative `./` / `../` specifiers
 * and does NOT attempt to walk node_modules. Package imports are recorded
 * under `externalImports` so skills can surface dependency surface area.
 */

export interface ImportGraph {
  readonly root: string;
  readonly scannedAt: string;
  readonly files: readonly string[];
  readonly edges: readonly ImportEdge[];
  readonly externalImports: readonly ExternalImport[];
  readonly unresolved: readonly UnresolvedImport[];
}

export interface ImportEdge {
  readonly from: string;
  readonly to: string;
}

export interface ExternalImport {
  readonly from: string;
  readonly specifier: string;
}

export interface UnresolvedImport {
  readonly from: string;
  readonly specifier: string;
  readonly reason: string;
}

const JS_TS_EXTS = [".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs"];
const SCANNABLE_EXTS = new Set(JS_TS_EXTS);

// Covers `import ... from "x"`, `import "x"`, `export ... from "x"`,
// `require("x")`, and dynamic `import("x")`. Ignores template-string imports.
const IMPORT_REGEX =
  /(?:^|[^\w$])(?:import\s+(?:[^'"`]*?from\s+)?|export\s+[^'"`]*?from\s+|require\s*\(|import\s*\()\s*(?:'([^']+)'|"([^"]+)")/g;

export function buildImportGraph(root: string): ImportGraph {
  const absRoot = path.resolve(root);
  if (!fs.existsSync(absRoot) || !fs.statSync(absRoot).isDirectory()) {
    throw new Error(`imports: root does not exist or is not a directory: ${absRoot}`);
  }

  const files = collectFiles(absRoot);
  const edges: ImportEdge[] = [];
  const externalImports: ExternalImport[] = [];
  const unresolved: UnresolvedImport[] = [];

  for (const file of files) {
    const src = safeRead(file);
    if (src === null) continue;
    const rel = path.relative(absRoot, file);
    for (const specifier of extractSpecifiers(src)) {
      if (isRelative(specifier)) {
        const resolved = resolveRelative(file, specifier);
        if (resolved && resolved.startsWith(absRoot)) {
          edges.push({ from: rel, to: path.relative(absRoot, resolved) });
        } else {
          unresolved.push({
            from: rel,
            specifier,
            reason: "relative target not found",
          });
        }
      } else if (isPackageSpecifier(specifier)) {
        externalImports.push({ from: rel, specifier });
      } else {
        // Absolute path imports and tsconfig paths — not resolved here.
        unresolved.push({
          from: rel,
          specifier,
          reason: "non-relative / tsconfig-path",
        });
      }
    }
  }

  return {
    root: absRoot,
    scannedAt: new Date().toISOString(),
    files: files.map((f) => path.relative(absRoot, f)).sort(),
    edges: edges.sort(edgeCompare),
    externalImports: externalImports.sort(externalCompare),
    unresolved,
  };
}

/**
 * Cycle detection over an adjacency list. Returns one canonical cycle per
 * SCC (strongly-connected component) so consumers can surface the loop
 * without drowning in redundant rotations.
 */
export function findCycles(graph: ImportGraph): string[][] {
  const adj = new Map<string, string[]>();
  for (const f of graph.files) adj.set(f, []);
  for (const e of graph.edges) {
    adj.get(e.from)?.push(e.to);
  }

  const index = new Map<string, number>();
  const lowlink = new Map<string, number>();
  const onStack = new Set<string>();
  const stack: string[] = [];
  const cycles: string[][] = [];
  let idx = 0;

  const strongConnect = (v: string): void => {
    index.set(v, idx);
    lowlink.set(v, idx);
    idx += 1;
    stack.push(v);
    onStack.add(v);

    for (const w of adj.get(v) ?? []) {
      if (!index.has(w)) {
        strongConnect(w);
        lowlink.set(v, Math.min(lowlink.get(v)!, lowlink.get(w)!));
      } else if (onStack.has(w)) {
        lowlink.set(v, Math.min(lowlink.get(v)!, index.get(w)!));
      }
    }

    if (lowlink.get(v) === index.get(v)) {
      const scc: string[] = [];
      while (true) {
        const w = stack.pop()!;
        onStack.delete(w);
        scc.push(w);
        if (w === v) break;
      }
      // Only record SCCs that represent true cycles: either >1 node, or a
      // self-loop (edge from v back to v).
      if (scc.length > 1) {
        cycles.push(scc.sort());
      } else if (scc.length === 1 && (adj.get(scc[0]!) ?? []).includes(scc[0]!)) {
        cycles.push([scc[0]!]);
      }
    }
  };

  for (const v of graph.files) {
    if (!index.has(v)) strongConnect(v);
  }

  return cycles.sort((a, b) => a[0]!.localeCompare(b[0]!));
}

export function extractSpecifiers(src: string): string[] {
  const out: string[] = [];
  IMPORT_REGEX.lastIndex = 0;
  // Strip line comments and /* block comments */ so commented-out imports
  // don't pollute the graph. Template literals are untouched — regex-level
  // heuristic, not a parser.
  const cleaned = src
    .replace(/\/\/.*$/gm, "")
    .replace(/\/\*[\s\S]*?\*\//g, "");
  let m: RegExpExecArray | null;
  while ((m = IMPORT_REGEX.exec(cleaned)) !== null) {
    const spec = m[1] ?? m[2];
    if (spec !== undefined && spec !== "") out.push(spec);
  }
  return out;
}

function collectFiles(root: string): string[] {
  const result: string[] = [];
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
        e.name === "build"
      ) {
        continue;
      }
      const full = path.join(current, e.name);
      if (e.isDirectory()) {
        stack.push(full);
      } else if (SCANNABLE_EXTS.has(path.extname(e.name).toLowerCase())) {
        result.push(full);
      }
    }
  }
  return result;
}

function safeRead(file: string): string | null {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return null;
  }
}

function isRelative(specifier: string): boolean {
  return specifier.startsWith("./") || specifier.startsWith("../");
}

function isPackageSpecifier(specifier: string): boolean {
  if (specifier === "") return false;
  if (specifier.startsWith("/")) return false;
  if (isRelative(specifier)) return false;
  // Scoped packages (@x/y), plain packages (lodash), built-ins (fs, node:fs).
  return /^(@[a-z0-9][\w.-]*\/)?[a-z0-9][\w.-]*/.test(specifier);
}

function resolveRelative(fromFile: string, specifier: string): string | null {
  const fromDir = path.dirname(fromFile);
  const baseAbs = path.resolve(fromDir, specifier);

  // Exact extension match.
  for (const ext of JS_TS_EXTS) {
    const candidate = baseAbs + ext;
    if (isFile(candidate)) return candidate;
  }
  // Bare path that already has an extension.
  if (isFile(baseAbs)) return baseAbs;
  // Directory with an index file.
  if (isDir(baseAbs)) {
    for (const ext of JS_TS_EXTS) {
      const candidate = path.join(baseAbs, `index${ext}`);
      if (isFile(candidate)) return candidate;
    }
  }
  return null;
}

function isFile(p: string): boolean {
  try {
    return fs.statSync(p).isFile();
  } catch {
    return false;
  }
}

function isDir(p: string): boolean {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function edgeCompare(a: ImportEdge, b: ImportEdge): number {
  return a.from.localeCompare(b.from) || a.to.localeCompare(b.to);
}

function externalCompare(a: ExternalImport, b: ExternalImport): number {
  return a.specifier.localeCompare(b.specifier) || a.from.localeCompare(b.from);
}
