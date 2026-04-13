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
export declare function scanDebt(opts: DebtScanOptions): DebtScanResult;
