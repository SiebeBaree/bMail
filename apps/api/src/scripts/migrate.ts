import { createDb } from "@repo/db";
import { migrate } from "drizzle-orm/neon-serverless/migrator";

// Runs as `vercel-build`, so a deploy migrates its own database and nobody migrates from their Mac. Only production
// builds do: preview builds usually share production's DATABASE_URL, and a branch's migration must not reach it before
// the branch ships.
const environment = process.env.VERCEL_ENV;
if (environment && environment !== "production") {
    process.stdout.write(`Skipping migrations in a ${environment} build.\n`);
    process.exit(0);
}
const url = process.env.DATABASE_URL;
if (!url) throw new Error("Set DATABASE_URL to migrate. On Vercel, add a Neon database to the project.");

const db = createDb(url);
await migrate(db, { migrationsFolder: new URL("../../../../packages/db/migrations", import.meta.url).pathname });
await db.$client.end();
process.stdout.write("Migrated.\n");
