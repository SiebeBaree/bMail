import { writeFile } from "node:fs/promises";

import { createDb } from "@repo/db";

import { buildApp } from "../app";
import { createAuth } from "../auth";
import { createMemoryStorage } from "../lib/storage";
import { createFakeResend } from "../test/fake-resend";

// Writes the OpenAPI document the Swift client is generated from. Nothing connects anywhere: the app is only built
// far enough to collect route schemas. Run `pnpm openapi` after changing a contract; CI fails when it's stale.
const output = new URL("../../../macos/MailKit/Sources/APIClient/openapi.json", import.meta.url);

const db = createDb("postgres://openapi:openapi@localhost/openapi");
const app = await buildApp({
    db,
    auth: createAuth({
        db,
        baseURL: "http://localhost",
        secret: "openapi-openapi-openapi-openapi-openapi",
        allowedEmails: [],
    }),
    resend: createFakeResend().gateway,
    storage: createMemoryStorage(),
    trackingSecret: "openapi",
    publicUrl: "http://localhost",
});
await app.ready();
// Two fixes for the generated Swift client:
// - zod marks every object closed, and swift-openapi-generator turns that into decoders that reject unknown keys. A
//   response that gains a field would then break every app build already installed, so objects stay open.
// - `204: z.null()` documents a JSON body, which the client then tries to decode from the empty response and fails
//   after the server already did the work. A 204 has no body.
const spec = JSON.stringify(
    withoutUnusedSchemas(app.swagger()),
    (key, value: unknown) => {
        if (key === "additionalProperties" && value === false) return undefined;
        if (key === "204" && typeof value === "object" && value !== null) return { ...value, content: undefined };
        return value;
    },
    2,
);
await writeFile(output, `${spec}\n`);
await app.close();
process.stdout.write(`Wrote ${output.pathname}\n`);

/**
 * The zod transform emits an input and an output variant of every named schema. Only the ones a route actually
 * references stay, so the Swift client has no dead types.
 */
function withoutUnusedSchemas<T extends { paths?: unknown; components?: { schemas?: Record<string, unknown> } }>(
    document: T,
): T {
    const schemas = document.components?.schemas ?? {};
    const used = new Set<string>();
    const visit = (node: unknown): void => {
        if (Array.isArray(node)) return node.forEach(visit);
        if (typeof node !== "object" || node === null) return;
        for (const [key, value] of Object.entries(node)) {
            if (key === "$ref" && typeof value === "string") {
                const name = value.replace("#/components/schemas/", "");
                if (!used.has(name)) {
                    used.add(name);
                    visit(schemas[name]);
                }
            } else visit(value);
        }
    };
    visit(document.paths);
    return {
        ...document,
        components: {
            ...document.components,
            schemas: Object.fromEntries(Object.entries(schemas).filter(([name]) => used.has(name))),
        },
    };
}
