import type { SentMessage, SyncResponse } from "@repo/contracts";
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

const draft = (overrides: Record<string, unknown> = {}) => ({
    id: crypto.randomUUID(),
    conversationId: crypto.randomUUID(),
    mailboxId,
    to: [{ name: "Jan Wouters", email: "jan@wouters.example" }],
    subject: "Proposal for Q4",
    html: '<p>Everything is in <a href="https://baree.be/proposal">the proposal</a>. <a href="mailto:siebe@baree.be">Mail me</a>.</p>',
    text: "Everything is in the proposal.",
    ...overrides,
});

const send = (body: Record<string, unknown>) =>
    harness.app.inject({ method: "POST", url: "/messages", headers, payload: body });

describe("POST /messages", () => {
    it("starts a conversation in Done and sends from the mailbox's address", async () => {
        const sent: SentMessage = expectStatus(await send(draft()), 200);
        expect(sent.conversation).toMatchObject({ folder: "done", isRead: true, subject: "Proposal for Q4" });
        expect(sent.message).toMatchObject({
            direction: "outbound",
            deliveryStatus: "sent",
            trackingEnabled: false,
            links: [],
        });

        const [outgoing] = harness.resend.sent;
        expect(outgoing?.email.from).toBe('"Siebe Baree" <siebe@baree.test>');
        expect(outgoing?.email.to).toEqual(['"Jan Wouters" <jan@wouters.example>']);
        expect(outgoing?.email.html).not.toContain("/o/");
    });

    it("replies in the thread with In-Reply-To and References", async () => {
        harness.resend.deliver({ id: "in_1", headers: { References: "<root@mail.example>" } });
        await harness.webhook({
            type: "email.received",
            created_at: new Date().toISOString(),
            data: { email_id: "in_1" },
        });
        const { conversations }: SyncResponse = expectStatus(
            await harness.app.inject({ method: "GET", url: "/sync", headers }),
            200,
        );

        expectStatus(
            await send(draft({ conversationId: conversations[0]?.id, subject: "Re: Contract draft v3" })),
            200,
        );
        expect(harness.resend.sent[0]?.email.headers).toEqual({
            "In-Reply-To": "<in_1@mail.example>",
            References: "<root@mail.example> <in_1@mail.example>",
        });
    });

    it("instruments the sent copy for tracking and keeps the stored html as written", async () => {
        const body = draft({ trackingEnabled: true });
        const sent: SentMessage = expectStatus(await send(body), 200);

        const html = harness.resend.sent[0]?.email.html ?? "";
        expect(html).toMatch(/<img src="http:\/\/api\.test\/o\/[0-9a-f-]{36}\.[\w-]{22}"/);
        expect(html).toMatch(/href="http:\/\/api\.test\/c\/[0-9a-f-]{36}\.[\w-]{22}"/);
        expect(html).toContain('href="mailto:siebe@baree.be"');
        expect(sent.message.html).toBe(body.html);
        expect(sent.message.links).toEqual([{ id: expect.any(String), url: "https://baree.be/proposal" }]);
    });

    it("sends once when the app retries the same message", async () => {
        const body = draft();
        expectStatus(await send(body), 200);
        expectStatus(await send(body), 200);
        expect(harness.resend.sent).toHaveLength(1);
    });

    it("can retry a send Resend refused, with the same links", async () => {
        const body = draft({ trackingEnabled: true });
        harness.resend.failNextSend("rate limited");
        const failed = await send(body);
        expect(failed.statusCode).toBe(502);
        expect(failed.json().message).toBe("rate limited");

        const sent: SentMessage = expectStatus(await send(body), 200);
        expect(sent.message.deliveryStatus).toBe("sent");
        expect(harness.resend.sent[0]?.email.html).toContain(`/c/${sent.message.links[0]?.id}.`);
    });

    it("refuses to send from a domain that isn't verified", async () => {
        const domain = expectStatus(
            await harness.app.inject({ method: "POST", url: "/domains", headers, payload: { name: "new.test" } }),
            201,
        );
        const mailbox = expectStatus(
            await harness.app.inject({
                method: "POST",
                url: "/mailboxes",
                headers,
                payload: { id: crypto.randomUUID(), domainId: domain.id, localPart: "hello", displayName: "Hello" },
            }),
            201,
        );
        const response = await send(draft({ mailboxId: mailbox.id }));
        expect(response.statusCode).toBe(409);
        expect(response.json().message).toBe("new.test isn't verified yet, so mail from it would bounce.");
    });

    it("attaches uploads and hands Resend a url to fetch them from", async () => {
        const upload = expectStatus(
            await harness.app.inject({
                method: "POST",
                url: "/uploads",
                headers,
                payload: { filename: "proposal.pdf", contentType: "application/pdf", size: 1200 },
            }),
            201,
        );
        const sent: SentMessage = expectStatus(await send(draft({ attachmentIds: [upload.id] })), 200);
        expect(sent.message.attachments).toEqual([
            expect.objectContaining({ id: upload.id, filename: "proposal.pdf" }),
        ]);
        expect(harness.resend.sent[0]?.email.attachments).toEqual([
            { filename: "proposal.pdf", contentType: "application/pdf", url: expect.stringContaining("proposal.pdf") },
        ]);
    });
});
