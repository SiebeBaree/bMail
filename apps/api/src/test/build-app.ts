import type { LightMyRequestResponse } from "fastify";

import { buildApp } from "../app";
import { createServerSettings } from "../lib/server-settings";
import { createMemoryStorage } from "../lib/storage";
import { createTestDb } from "./db";
import { createFakeResend } from "./fake-resend";

export const PUBLIC_URL = "http://api.test";
export const CLAIM_CODE = "the-claim-code";

export async function buildTestApp() {
    const { db, reset, close } = await createTestDb();
    const resend = createFakeResend();
    const storage = createMemoryStorage();
    const app = await buildApp({
        db,
        settings: createServerSettings(db),
        resend: resend.gateway,
        storage,
        trackingSecret: "test-tracking-secret-0123456789abcdef",
        publicUrl: PUBLIC_URL,
        claimCode: CLAIM_CODE,
    });
    await app.ready();

    /** Claims the fresh server the way the app does and returns the bearer header it would send. */
    async function claim(): Promise<{ authorization: string }> {
        const { token } = expectStatus(await app.inject({ method: "POST", url: "/claim", payload: {} }), 200);
        return { authorization: `Bearer ${token}` };
    }

    /** A verified domain with one mailbox, the state every mail test starts from. */
    async function seedMailbox(headers: { authorization: string }, domain = "baree.test", localPart = "siebe") {
        const created = expectStatus(
            await app.inject({ method: "POST", url: "/domains", headers, payload: { name: domain } }),
            201,
        );
        resend.verifyDomain(domain);
        expectStatus(await app.inject({ method: "POST", url: `/domains/${created.id}/verify`, headers }), 200);
        const mailbox = expectStatus(
            await app.inject({
                method: "POST",
                url: "/mailboxes",
                headers,
                payload: { id: crypto.randomUUID(), domainId: created.id, localPart, displayName: "Siebe Baree" },
            }),
            201,
        );
        return { domainId: String(created.id), mailboxId: String(mailbox.id) };
    }

    /** Posts a Resend webhook the way Resend would, signature included. */
    function webhook(event: unknown, svixId: string = crypto.randomUUID()) {
        return app.inject({
            method: "POST",
            url: "/webhooks/resend",
            headers: { "content-type": "application/json", "svix-id": svixId, "svix-signature": "valid" },
            payload: JSON.stringify(event),
        });
    }

    return {
        app,
        db,
        resend,
        storage,
        claim,
        seedMailbox,
        webhook,
        reset: async () => {
            await reset();
            resend.sent.length = 0;
            resend.webhooks.length = 0;
            storage.objects.clear();
        },
        close: async () => {
            await app.close();
            await close();
        },
    };
}

export type TestHarness = Awaited<ReturnType<typeof buildTestApp>>;

/** Asserts the status and returns the parsed body, with the actual body in the failure message. */
export function expectStatus(response: LightMyRequestResponse, status: number) {
    if (response.statusCode !== status) {
        throw new Error(`expected ${status}, got ${response.statusCode}: ${response.body}`);
    }
    return response.body ? response.json() : null;
}
