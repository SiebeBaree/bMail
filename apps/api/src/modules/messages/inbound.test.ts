import type { SyncResponse } from "@repo/contracts";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { buildTestApp, expectStatus, type TestHarness } from "../../test/build-app";

let harness: TestHarness;
let headers: { authorization: string };
let mailboxId: string;

beforeAll(async () => {
    harness = await buildTestApp();
});
afterAll(() => harness.close());
beforeEach(async () => {
    await harness.reset();
    headers = await harness.claim();
    ({ mailboxId } = await harness.seedMailbox(headers));
});

const received = (emailId: string) => ({
    type: "email.received",
    created_at: new Date().toISOString(),
    data: { email_id: emailId },
});

async function sync(): Promise<SyncResponse> {
    return expectStatus(await harness.app.inject({ method: "GET", url: "/sync", headers }), 200);
}

describe("email.received", () => {
    it("stores the mail in a new inbox conversation of the mailbox it was sent to", async () => {
        harness.resend.deliver({ id: "in_1" });
        expectStatus(await harness.webhook(received("in_1")), 204);

        const { conversations, messages } = await sync();
        expect(conversations).toEqual([
            expect.objectContaining({ mailboxId, subject: "Contract draft v3", folder: "inbox", isRead: false }),
        ]);
        expect(messages[0]).toMatchObject({
            direction: "inbound",
            from: { name: "Lena Peeters", email: "lena@peeters.example" },
            messageIdHeader: "<in_1@mail.example>",
            snippet: "Added the clauses we discussed.",
        });
    });

    it("threads a reply into its conversation and brings it back from Done", async () => {
        harness.resend.deliver({ id: "in_1" });
        await harness.webhook(received("in_1"));
        const [conversation] = (await sync()).conversations;
        await harness.app.inject({
            method: "PATCH",
            url: `/conversations/${conversation?.id}`,
            headers,
            payload: { folder: "done", isRead: true },
        });

        harness.resend.deliver({
            id: "in_2",
            subject: "Re: Contract draft v3",
            headers: { "In-Reply-To": "<in_1@mail.example>" },
        });
        await harness.webhook(received("in_2"));

        const { conversations, messages } = await sync();
        expect(conversations).toHaveLength(1);
        expect(conversations[0]).toMatchObject({ folder: "inbox", isRead: false });
        expect(messages.map((message) => message.conversationId)).toEqual([conversation?.id, conversation?.id]);
    });

    it("keeps the List-Unsubscribe header and whether it supports one-click", async () => {
        harness.resend.deliver({
            id: "in_1",
            headers: {
                "List-Unsubscribe": "<https://news.example/u/1>, <mailto:unsubscribe@news.example>",
                "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
            },
        });
        await harness.webhook(received("in_1"));

        expect((await sync()).messages[0]).toMatchObject({
            listUnsubscribe: "<https://news.example/u/1>, <mailto:unsubscribe@news.example>",
            listUnsubscribeOneClick: true,
        });
    });

    it("sends mail for an address without a mailbox to the catch-all", async () => {
        harness.resend.deliver({ id: "in_1", to: ["Whoever <random@baree.test>"] });
        await harness.webhook(received("in_1"));
        expect((await sync()).conversations[0]?.mailboxId).toBe(mailboxId);
    });

    it("ignores mail for domains it doesn't own", async () => {
        harness.resend.deliver({ id: "in_1", to: ["someone@elsewhere.example"] });
        expectStatus(await harness.webhook(received("in_1")), 204);
        expect((await sync()).conversations).toEqual([]);
    });

    it("stores a retried webhook once", async () => {
        harness.resend.deliver({ id: "in_1" });
        await harness.webhook(received("in_1"));
        await harness.webhook(received("in_1"));
        expect((await sync()).messages).toHaveLength(1);
    });

    it("copies attachments out of Resend into storage", async () => {
        const pdf = Buffer.from("%PDF-1.7 contract");
        harness.resend.deliver({ id: "in_1" }, [
            {
                id: "att_1",
                filename: "contract.pdf",
                contentType: "application/pdf",
                size: pdf.length,
                contentId: null,
                downloadUrl: `data:application/pdf;base64,${pdf.toString("base64")}`,
            },
        ]);
        await harness.webhook(received("in_1"));

        const [message] = (await sync()).messages;
        expect(message?.attachments).toEqual([expect.objectContaining({ filename: "contract.pdf", size: pdf.length })]);
        expect(Buffer.from(harness.storage.objects.get("inbound/in_1/att_1/contract.pdf") ?? []).toString()).toBe(
            "%PDF-1.7 contract",
        );
    });

    it("rejects a webhook with a bad signature", async () => {
        const response = await harness.app.inject({
            method: "POST",
            url: "/webhooks/resend",
            headers: { "content-type": "application/json", "svix-id": "x", "svix-signature": "forged" },
            payload: JSON.stringify(received("in_1")),
        });
        expect(response.statusCode).toBe(400);
    });
});
