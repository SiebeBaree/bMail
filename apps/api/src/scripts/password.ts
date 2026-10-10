import { randomBytes } from "node:crypto";

import { createDb } from "@repo/db";
import { env } from "@repo/env/api";

import { createAuth, setPassword } from "../auth";

// pnpm --filter api password you@example.com
// Prints a new password for an email in ALLOWED_EMAILS, creating its account the first time. Run it again to replace a
// lost password, which also signs out every device. It writes to DATABASE_URL, so point that at the server's database.
const email = process.argv[2]?.trim().toLowerCase();
if (!email) throw new Error("Usage: pnpm --filter api password you@example.com");

const db = createDb(env.DATABASE_URL);
const auth = createAuth({
    db,
    baseURL: env.PUBLIC_URL,
    secret: env.BETTER_AUTH_SECRET,
    allowedEmails: env.ALLOWED_EMAILS,
});
const password = randomBytes(18).toString("base64url");
await setPassword(auth, email, password);

process.stdout.write(`Sign in to bMail as ${email} with this password:\n\n    ${password}\n\n`);
process.exit(0);
