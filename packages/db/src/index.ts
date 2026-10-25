import { Pool } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-serverless";

import * as schema from "./schema";

// The WebSocket driver rather than neon-http: inbound mail, sending and claiming all need interactive transactions.
export function createDb(connectionString: string) {
    return drizzle(new Pool({ connectionString }), { schema, casing: "snake_case" });
}

// The api is written against this interface so tests can swap in a PGlite-backed drizzle instance.
export type Database = ReturnType<typeof createDb>;
export type Transaction = Parameters<Parameters<Database["transaction"]>[0]>[0];

export * from "./schema";
export { schema };
