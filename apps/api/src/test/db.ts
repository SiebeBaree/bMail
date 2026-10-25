import { PGlite } from "@electric-sql/pglite";
import { schema, type Database } from "@repo/db";
import { sql } from "drizzle-orm";
import { drizzle } from "drizzle-orm/pglite";
import { migrate } from "drizzle-orm/pglite/migrator";

// A real in-memory Postgres with the real migrations applied (triggers included), so integration tests exercise actual
// SQL without Neon.
export async function createTestDb() {
    const client = new PGlite();
    const db = drizzle(client, { schema, casing: "snake_case" });
    await migrate(db, { migrationsFolder: new URL("../../../../packages/db/migrations", import.meta.url).pathname });

    return {
        db: db as unknown as Database,
        reset: async () => {
            await db.execute(sql`truncate "user", server_settings, webhook_receipts restart identity cascade`);
        },
        close: () => client.close(),
    };
}
