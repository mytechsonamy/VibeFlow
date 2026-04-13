import * as fs from "node:fs";
import * as path from "node:path";
const FRAMEWORK_PACKAGES = new Map([
    ["fastify", "fastify"],
    ["express", "express"],
    ["@nestjs/core", "nestjs"],
    ["next", "next.js"],
    ["react", "react"],
    ["react-dom", "react"],
    ["vue", "vue"],
    ["@angular/core", "angular"],
    ["svelte", "svelte"],
    ["hono", "hono"],
    ["koa", "koa"],
]);
const TEST_RUNNER_PACKAGES = new Map([
    ["vitest", "vitest"],
    ["jest", "jest"],
    ["mocha", "mocha"],
    ["ava", "ava"],
    ["@playwright/test", "playwright"],
    ["cypress", "cypress"],
]);
const BUILD_TOOL_PACKAGES = new Map([
    ["vite", "vite"],
    ["webpack", "webpack"],
    ["rollup", "rollup"],
    ["esbuild", "esbuild"],
    ["tsup", "tsup"],
    ["parcel", "parcel"],
    ["turbo", "turborepo"],
]);
export async function scanRepo(root) {
    const absRoot = path.resolve(root);
    if (!fs.existsSync(absRoot) || !fs.statSync(absRoot).isDirectory()) {
        throw new Error(`scanner: root does not exist or is not a directory: ${absRoot}`);
    }
    const languages = new FindingSet();
    const frameworks = new FindingSet();
    const testRunners = new FindingSet();
    const buildTools = new FindingSet();
    const pkgJsonPath = path.join(absRoot, "package.json");
    if (fs.existsSync(pkgJsonPath)) {
        languages.add("javascript", [relFrom(absRoot, pkgJsonPath)], 0.85);
        const pkg = safeReadJson(pkgJsonPath);
        const deps = collectDeps(pkg);
        for (const [dep, label] of FRAMEWORK_PACKAGES) {
            if (deps.has(dep)) {
                frameworks.add(label, [relFrom(absRoot, pkgJsonPath)], 0.85);
            }
        }
        for (const [dep, label] of TEST_RUNNER_PACKAGES) {
            if (deps.has(dep)) {
                testRunners.add(label, [relFrom(absRoot, pkgJsonPath)], 0.85);
            }
        }
        for (const [dep, label] of BUILD_TOOL_PACKAGES) {
            if (deps.has(dep)) {
                buildTools.add(label, [relFrom(absRoot, pkgJsonPath)], 0.85);
            }
        }
    }
    const tsconfigPath = path.join(absRoot, "tsconfig.json");
    if (fs.existsSync(tsconfigPath)) {
        // tsconfig promotes the javascript finding to typescript with higher
        // confidence — it's a manifest-level confirmation.
        languages.upgrade("typescript", [relFrom(absRoot, tsconfigPath)], 0.95);
        languages.remove("javascript");
        buildTools.add("tsc", [relFrom(absRoot, tsconfigPath)], 0.9);
    }
    // Vitest/Jest config files are a second signal — bump confidence when present.
    for (const candidate of [
        "vitest.config.ts",
        "vitest.config.js",
        "vitest.config.mts",
    ]) {
        const p = path.join(absRoot, candidate);
        if (fs.existsSync(p)) {
            testRunners.upgrade("vitest", [relFrom(absRoot, p)], 0.98);
            break;
        }
    }
    for (const candidate of ["jest.config.ts", "jest.config.js", "jest.config.cjs"]) {
        const p = path.join(absRoot, candidate);
        if (fs.existsSync(p)) {
            testRunners.upgrade("jest", [relFrom(absRoot, p)], 0.98);
            break;
        }
    }
    // Python.
    const pyproject = path.join(absRoot, "pyproject.toml");
    if (fs.existsSync(pyproject)) {
        languages.add("python", [relFrom(absRoot, pyproject)], 0.9);
    }
    else if (fs.existsSync(path.join(absRoot, "requirements.txt"))) {
        languages.add("python", ["requirements.txt"], 0.75);
    }
    // Go.
    if (fs.existsSync(path.join(absRoot, "go.mod"))) {
        languages.add("go", ["go.mod"], 0.95);
    }
    // Rust.
    if (fs.existsSync(path.join(absRoot, "Cargo.toml"))) {
        languages.add("rust", ["Cargo.toml"], 0.95);
    }
    if (languages.isEmpty()) {
        // Directory-heuristic fallback: look at file extensions in src/.
        const srcDir = path.join(absRoot, "src");
        if (fs.existsSync(srcDir) && fs.statSync(srcDir).isDirectory()) {
            const extCounts = countExtensions(srcDir);
            for (const [lang, count] of detectLanguagesFromExt(extCounts)) {
                if (count > 0) {
                    languages.add(lang, ["src/ (heuristic)"], 0.5);
                }
            }
        }
    }
    return {
        root: absRoot,
        scannedAt: new Date().toISOString(),
        languages: languages.toArray(),
        frameworks: frameworks.toArray(),
        testRunners: testRunners.toArray(),
        buildTools: buildTools.toArray(),
    };
}
class FindingSet {
    map = new Map();
    add(name, evidence, confidence) {
        const existing = this.map.get(name);
        if (existing) {
            for (const e of evidence)
                existing.evidence.add(e);
            existing.confidence = Math.max(existing.confidence, confidence);
            return;
        }
        this.map.set(name, {
            evidence: new Set(evidence),
            confidence,
        });
    }
    upgrade(name, evidence, confidence) {
        this.add(name, evidence, confidence);
    }
    remove(name) {
        this.map.delete(name);
    }
    isEmpty() {
        return this.map.size === 0;
    }
    toArray() {
        return [...this.map.entries()]
            .map(([name, { evidence, confidence }]) => ({
            name,
            evidence: [...evidence].sort(),
            confidence,
        }))
            .sort((a, b) => a.name.localeCompare(b.name));
    }
}
function safeReadJson(p) {
    try {
        return JSON.parse(fs.readFileSync(p, "utf8"));
    }
    catch {
        return null;
    }
}
function collectDeps(pkg) {
    const out = new Set();
    if (!pkg || typeof pkg !== "object")
        return out;
    const obj = pkg;
    for (const key of ["dependencies", "devDependencies", "peerDependencies"]) {
        const section = obj[key];
        if (section && typeof section === "object") {
            for (const dep of Object.keys(section)) {
                out.add(dep);
            }
        }
    }
    return out;
}
function relFrom(root, abs) {
    return path.relative(root, abs) || path.basename(abs);
}
function countExtensions(dir) {
    const counts = new Map();
    const stack = [dir];
    while (stack.length > 0) {
        const current = stack.pop();
        let entries = [];
        try {
            entries = fs.readdirSync(current, { withFileTypes: true });
        }
        catch {
            continue;
        }
        for (const e of entries) {
            if (e.name.startsWith(".") || e.name === "node_modules")
                continue;
            const full = path.join(current, e.name);
            if (e.isDirectory()) {
                stack.push(full);
            }
            else {
                const ext = path.extname(e.name).toLowerCase();
                counts.set(ext, (counts.get(ext) ?? 0) + 1);
            }
        }
    }
    return counts;
}
function detectLanguagesFromExt(counts) {
    const out = [];
    const ts = (counts.get(".ts") ?? 0) + (counts.get(".tsx") ?? 0);
    const js = (counts.get(".js") ?? 0) + (counts.get(".jsx") ?? 0);
    const py = counts.get(".py") ?? 0;
    const go = counts.get(".go") ?? 0;
    const rs = counts.get(".rs") ?? 0;
    if (ts > 0)
        out.push(["typescript", ts]);
    if (js > 0 && ts === 0)
        out.push(["javascript", js]);
    if (py > 0)
        out.push(["python", py]);
    if (go > 0)
        out.push(["go", go]);
    if (rs > 0)
        out.push(["rust", rs]);
    return out;
}
//# sourceMappingURL=scanner.js.map