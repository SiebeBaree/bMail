import { defineConfig } from "drizzle-kit";

export default defineConfig({
    schema: "./src/schema/index.ts",
    out: "./migrations",
    dialect: "postgresql",
    casing: "snake_case",
    dbCredentials: {
        // Only needed for db:migrate / db:studio, not for db:generate.
        url: process.env.DATABASE_URL ?? "",
    },
});
