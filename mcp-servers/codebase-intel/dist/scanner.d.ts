/**
 * Language, framework, test runner, and build tool detection for a project
 * root. Every finding carries the list of files that justified it, so
 * downstream skills can audit the inference rather than trusting a label.
 *
 * Detection priority (never guess):
 *   1. Package manifest: package.json, pyproject.toml, go.mod, Cargo.toml
 *   2. Config files that confirm the manifest: tsconfig.json, vitest.config.*
 *   3. Directory heuristics — last resort, confidence <= 0.5
 */
export interface Finding {
    readonly name: string;
    readonly evidence: readonly string[];
    readonly confidence: number;
}
export interface ScanResult {
    readonly root: string;
    readonly scannedAt: string;
    readonly languages: readonly Finding[];
    readonly frameworks: readonly Finding[];
    readonly testRunners: readonly Finding[];
    readonly buildTools: readonly Finding[];
}
export declare function scanRepo(root: string): Promise<ScanResult>;
