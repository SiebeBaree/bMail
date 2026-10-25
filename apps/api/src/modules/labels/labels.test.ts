import type { Label, SyncResponse } from "@repo/contracts";
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
    headers = await harness.claim();
});

const createLabel = (name: string, id: string = crypto.randomUUID()) =>
    harness.app.inject({ method: "POST", url: "/labels", headers, payload: { id, name } });
const setLabels = (conversationId: string, labelIds: string[]) =>
    harness.app.inject({
        method: "PUT",
        url: `/conversations/${conversationId}/labels`,
        headers,
        payload: { labelIds },
    });

async function sync(cursor = 0): Promise<SyncResponse> {
    return expectStatus(await harness.app.inject({ method: "GET", url: `/sync?cursor=${cursor}`, headers }), 200);
}

describe("labels", () => {
    it("creates, renames and removes a label", async () => {
        const label: Label = expectStatus(await createLabel("  Work "), 201);
        expect(label).toMatchObject({ name: "Work", deletedAt: null });

        const renamed = expectStatus(
            await harness.app.inject({
                method: "PATCH",
                url: `/labels/${label.id}`,
                headers,
                payload: { name: "Clients" },
            }),
            200,
        );
        expect(renamed).toMatchObject({ id: label.id, name: "Clients" });

        expectStatus(await harness.app.inject({ method: "DELETE", url: `/labels/${label.id}`, headers }), 204);
        expect((await sync()).labels).toEqual([
            expect.objectContaining({ id: label.id, name: "Clients", deletedAt: expect.any(String) }),
        ]);
    });

    it("returns the same label for a retried create", async () => {
        const id = crypto.randomUUID();
        const first: Label = expectStatus(await createLabel("Work", id), 201);
        expect(expectStatus(await createLabel("Work", id), 201)).toEqual(first);
    });

    it("refuses a name that is already taken in any casing, until that label is removed", async () => {
        const label: Label = expectStatus(await createLabel("Work"), 201);
        const response = await createLabel("work");
        expect(response.statusCode).toBe(409);
        expect(response.json().message).toBe("There's already a label called work.");

        await harness.app.inject({ method: "DELETE", url: `/labels/${label.id}`, headers });
        expect((await createLabel("work")).statusCode).toBe(201);
    });
});

describe("PUT /conversations/:id/labels", () => {
    it("labels a conversation the api has never seen and syncs each new set", async () => {
        const work: Label = expectStatus(await createLabel("Work"), 201);
        const urgent: Label = expectStatus(await createLabel("Urgent"), 201);
        const gmailConversationId = crypto.randomUUID();

        expect(expectStatus(await setLabels(gmailConversationId, [work.id, urgent.id]), 200)).toEqual({
            conversationId: gmailConversationId,
            labelIds: [work.id, urgent.id],
        });
        const first = await sync();
        expect(first.conversationLabels).toEqual([
            { conversationId: gmailConversationId, labelIds: [work.id, urgent.id] },
        ]);

        expectStatus(await setLabels(gmailConversationId, [urgent.id]), 200);
        expect((await sync(first.cursor)).conversationLabels).toEqual([
            { conversationId: gmailConversationId, labelIds: [urgent.id] },
        ]);
    });

    it("rejects a removed label", async () => {
        const label: Label = expectStatus(await createLabel("Work"), 201);
        await harness.app.inject({ method: "DELETE", url: `/labels/${label.id}`, headers });
        expect((await setLabels(crypto.randomUUID(), [label.id])).statusCode).toBe(404);
    });

    it("takes a removed label off every conversation", async () => {
        const work: Label = expectStatus(await createLabel("Work"), 201);
        const urgent: Label = expectStatus(await createLabel("Urgent"), 201);
        const conversationId = crypto.randomUUID();
        await setLabels(conversationId, [work.id, urgent.id]);
        const { cursor } = await sync();

        await harness.app.inject({ method: "DELETE", url: `/labels/${work.id}`, headers });
        expect((await sync(cursor)).conversationLabels).toEqual([{ conversationId, labelIds: [urgent.id] }]);
    });
});
