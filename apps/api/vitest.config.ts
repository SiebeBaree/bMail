import { defineConfig } from "vitest/config";

export default defineConfig({
    test: {
        include: ["src/**/*.test.ts"],
        // Every file boots its own PGlite and runs the migrations, which takes a few seconds when files run in parallel.
        hookTimeout: 60_000,
    },
});
