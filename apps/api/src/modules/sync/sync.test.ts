import type { SyncResponse } from "@repo/contracts";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { buildTestApp, expectStatus, type TestHarness } from "../../test/build-app";

let harness: TestHarness;
let headers: { authorization: string };

beforeAll(async () => {
    harness = await buildTestApp();
});
afterAll(() => harness.close());
beforeEach(async () => {
    await harness.reset();
    headers = await harness.signIn();
    await harness.seedMailbox(headers);
});

async function sync(cursor = 0, limit = 200): Promise<SyncResponse> {
    return expectStatus(
        await harness.app.inject({ method: "GET", url: `/sync?cursor=${cursor}&limit=${limit}`, headers }),
        200,
    );
}

async function receive(count: number) {
    for (let index = 0; index < count; index++) {
        harness.resend.deliver({ id: `in_${index}`, subject: `Mail ${index}` });
        await harness.webhook({
            type: "email.received",
            created_at: new Date().toISOString(),
            data: { email_id: `in_${index}` },
        });
    }
}

describe("GET /sync", () => {
    it("returns only what changed after the cursor", async () => {
        const first = await sync();
        expect(first.domains).toHaveLength(1);
        expect(first.mailboxes).toEqual([expect.objectContaining({ address: "siebe@baree.test" })]);

        await receive(1);
        const second = await sync(first.cursor);
        expect(second.domains).toEqual([]);
        expect(second.conversations.map((conversation) => conversation.subject)).toEqual(["Mail 0"]);
        expect(second.cursor).toBeGreaterThan(first.cursor);

        expect(await sync(second.cursor)).toMatchObject({ conversations: [], messages: [], hasMore: false });
    });

    it("pages through a backlog without losing or repeating rows", async () => {
        await receive(5);
        const subjects: string[] = [];
        let cursor = 0;
        for (let page = 0; page < 10; page++) {
            const response = await sync(cursor, 2);
            subjects.push(...response.conversations.map((conversation) => conversation.subject));
            cursor = response.cursor;
            if (!response.hasMore) break;
        }
        expect(subjects.toSorted()).toEqual(["Mail 0", "Mail 1", "Mail 2", "Mail 3", "Mail 4"]);
    });

    it("sends a message's conversation along when the conversation changed since", async () => {
        await receive(3);
        const { conversations } = await sync();
        // Starring moves the first conversation past its message in seq order.
        await harness.app.inject({
            method: "PATCH",
            url: `/conversations/${conversations[0]?.id}`,
            headers,
            payload: { isStarred: true },
        });
        // What a fresh install has after each page.
        const known = new Set<string>();
        let cursor = 0;
        for (let page = 0; page < 10; page++) {
            const response = await sync(cursor, 1);
            for (const conversation of response.conversations) known.add(conversation.id);
            for (const message of response.messages) expect(known).toContain(message.conversationId);
            cursor = response.cursor;
            if (!response.hasMore) break;
        }
    });

    it("sends a conversation again after it changes", async () => {
        await receive(1);
        const { cursor, conversations } = await sync();
        await harness.app.inject({
            method: "PATCH",
            url: `/conversations/${conversations[0]?.id}`,
            headers,
            payload: { isStarred: true },
        });
        expect((await sync(cursor)).conversations).toEqual([expect.objectContaining({ isStarred: true })]);
    });
});
