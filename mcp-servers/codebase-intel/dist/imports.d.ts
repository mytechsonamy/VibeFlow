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
export declare function buildImportGraph(root: string): ImportGraph;
/**
 * Cycle detection over an adjacency list. Returns one canonical cycle per
 * SCC (strongly-connected component) so consumers can surface the loop
 * without drowning in redundant rotations.
 */
export declare function findCycles(graph: ImportGraph): string[][];
export declare function extractSpecifiers(src: string): string[];
