/**
 * Test-runner reporter parsers.
 *
 * Every framework the skill supports has its own JSON reporter shape.
 * This module is the only place that knows about those shapes; every
 * downstream module (metrics, flakiness, trends, dashboard) consumes
 * the `NormalizedRun` type produced here.
 *
 * Adding a new framework means:
 *   1. Add a `parseX` function below
 *   2. Teach `autoDetect` to recognize its shape
 *   3. Add its name to the `ReporterFramework` union
 *   4. Extend the integration harness `framework` sentinel
 */
export type ReporterFramework = "vitest" | "jest" | "playwright";
export interface NormalizedTest {
    /** Stable identifier: `<file>::<name>`. Used as the flakiness key. */
    readonly id: string;
    readonly file: string;
    readonly name: string;
    readonly status: "passed" | "failed" | "skipped" | "pending";
    readonly durationMs: number | null;
    readonly errorMessage: string | null;
    /** 0 when the framework doesn't track retries. */
    readonly retries: number;
}
export interface NormalizedRun {
    readonly framework: ReporterFramework;
    readonly startedAt: string;
    readonly finishedAt: string;
    readonly totalDurationMs: number;
    readonly tests: readonly NormalizedTest[];
}
export declare class ReporterParseError extends Error {
    constructor(message: string);
}
/**
 * Parse a reporter payload without the caller having to name the
 * framework. Returns the normalized run; throws on malformed input
 * rather than guessing.
 */
export declare function parseReporter(raw: unknown): NormalizedRun;
export declare function autoDetect(raw: unknown): ReporterFramework;
interface VitestReport {
    numTotalTests?: number;
    startTime?: number;
    endTime?: number;
    testResults?: VitestFileResult[];
    config?: {
        name?: string;
    };
}
interface VitestFileResult {
    name?: string;
    testFilePath?: string;
    startTime?: number;
    endTime?: number;
    assertionResults?: VitestAssertion[];
}
interface VitestAssertion {
    ancestorTitles?: string[];
    title?: string;
    fullName?: string;
    status?: string;
    duration?: number;
    failureMessages?: string[];
    invocations?: number;
    retryReasons?: unknown[];
    location?: {
        line?: number;
        column?: number;
    };
}
type JestReport = VitestReport;
export declare function parseVitest(raw: VitestReport): NormalizedRun;
export declare function parseJest(raw: JestReport): NormalizedRun;
interface PlaywrightReport {
    config: {
        version?: string;
    };
    suites: PlaywrightSuite[];
    stats?: {
        startTime?: string;
        duration?: number;
    };
}
interface PlaywrightSuite {
    file?: string;
    title?: string;
    suites?: PlaywrightSuite[];
    specs?: PlaywrightSpec[];
}
interface PlaywrightSpec {
    id?: string;
    title?: string;
    file?: string;
    tests?: PlaywrightTestRow[];
}
interface PlaywrightTestRow {
    results?: PlaywrightResult[];
    projectName?: string;
}
interface PlaywrightResult {
    status?: string;
    duration?: number;
    error?: {
        message?: string;
    };
    retry?: number;
}
export declare function parsePlaywright(raw: PlaywrightReport): NormalizedRun;
export {};
