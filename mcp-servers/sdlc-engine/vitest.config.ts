import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
    environment: "node",
    testTimeout: 15000,
    coverage: {
      provider: "v8",
      reporter: ["text", "json-summary"],
      include: ["src/**/*.ts"],
      // src/index.ts is the stdio bootstrap — it wires transport +
      // process.exit handlers and cannot be exercised from vitest.
      // The integration harness (tests/integration/run.sh [4]) smokes
      // the full stdio path end-to-end, which is the correct place
      // for that coverage.
      exclude: ["src/index.ts"],
      thresholds: {
        statements: 80,
        lines: 80,
        functions: 80,
        branches: 80,
      },
    },
  },
});
