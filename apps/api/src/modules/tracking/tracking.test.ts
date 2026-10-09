import type { SentMessage, SyncResponse } from "@repo/contracts";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import { buildTestApp, expectStatus, type TestHarness } from "../../test/build-app";

let harness: TestHarness;
let headers: { authorization: string };
let sent: SentMessage;

beforeAll(async () => {
    harness = await buildTestApp();
});
afterAll(() => harness.close());
beforeEach(async () => {
    vi.useRealTimers();
    await harness.reset();
    headers = await harness.signIn();
    const { mailboxId } = await harness.seedMailbox(headers);
    sent = expectStatus(
        await harness.app.inject({
            method: "POST",
            url: "/messages",
            headers,
            payload: {
                id: crypto.randomUUID(),
                conversationId: crypto.randomUUID(),
                mailboxId,
                to: [{ email: "jan@wouters.example" }],
                subject: "Proposal for Q4",
                html: '<p><a href="https://baree.be/proposal">Proposal</a></p>',
                text: "Proposal",
                trackingEnabled: true,
            },
        }),
        200,
    );
});

const sentHtml = () => harness.resend.sent[0]?.email.html ?? "";
const pixelPath = () => new URL(/<img src="([^"]+)"/.exec(sentHtml())?.[1] ?? "").pathname;
const clickPath = () => new URL(/href="([^"]+\/c\/[^"]+)"/.exec(sentHtml())?.[1] ?? "").pathname;
const aMinuteLater = () => vi.useFakeTimers({ now: Date.now() + 60_000, toFake: ["Date"] });
const userAgents = {
    mac: "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko)",
    appleProxy: "Mozilla/5.0",
    gmail: "Mozilla/5.0 (Windows NT 5.1; rv:11.0) Gecko Firefox/11.0 (via ggpht.com GoogleImageProxy)",
    windowsChrome:
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
};

async function events() {
    const response: SyncResponse = expectStatus(
        await harness.app.inject({ method: "GET", url: "/sync", headers }),
        200,
    );
    return response.events.filter((event) => event.type === "opened" || event.type === "clicked");
}

describe("GET /o/:token", () => {
    it("records an open by a person with their device and location", async () => {
        aMinuteLater();
        const response = await harness.app.inject({
            method: "GET",
            url: pixelPath(),
            headers: { "user-agent": userAgents.mac, "x-vercel-ip-city": "Ghent", "x-vercel-ip-country": "BE" },
        });
        expect(response.statusCode).toBe(200);
        expect(response.headers["content-type"]).toBe("image/gif");
        expect(response.headers["cache-control"]).toContain("no-store");
        expect(await events()).toEqual([
            expect.objectContaining({
                type: "opened",
                source: "person",
                device: "Mac · Apple Mail",
                city: "Ghent",
                country: "BE",
            }),
        ]);
    });

    it("tells Apple's privacy proxy and Google's image proxy apart from people", async () => {
        aMinuteLater();
        await harness.app.inject({ method: "GET", url: pixelPath(), headers: { "user-agent": userAgents.appleProxy } });
        await harness.app.inject({ method: "GET", url: pixelPath(), headers: { "user-agent": userAgents.gmail } });
        expect((await events()).map((event) => event.source)).toEqual(["apple_proxy", "google_proxy"]);
    });

    it("counts an open seconds after sending as a scanner, whatever the user agent", async () => {
        await harness.app.inject({
            method: "GET",
            url: pixelPath(),
            headers: { "user-agent": userAgents.windowsChrome },
        });
        expect((await events())[0]?.source).toBe("scanner");
    });

    it("still answers with the pixel for a forged token, and records nothing", async () => {
        const forged = pixelPath().replace(/\.[\w-]+$/, ".AAAAAAAAAAAAAAAAAAAAAA");
        const response = await harness.app.inject({ method: "GET", url: forged });
        expect(response.statusCode).toBe(200);
        expect(response.headers["content-type"]).toBe("image/gif");
        expect(await events()).toEqual([]);
    });
});

describe("GET /c/:token", () => {
    it("redirects to the original link and records the click", async () => {
        aMinuteLater();
        const response = await harness.app.inject({
            method: "GET",
            url: clickPath(),
            headers: { "user-agent": userAgents.mac },
        });
        expect(response.statusCode).toBe(302);
        expect(response.headers.location).toBe("https://baree.be/proposal");
        expect(await events()).toEqual([
            expect.objectContaining({
                type: "clicked",
                source: "person",
                url: "https://baree.be/proposal",
                messageId: sent.message.id,
            }),
        ]);
    });

    it("counts a click seconds after sending as a link scanner", async () => {
        await harness.app.inject({ method: "GET", url: clickPath(), headers: { "user-agent": userAgents.mac } });
        expect((await events())[0]?.source).toBe("scanner");
    });

    it("answers 404 for a token that wasn't signed by us", async () => {
        const response = await harness.app.inject({
            method: "GET",
            url: `/c/${crypto.randomUUID()}.AAAAAAAAAAAAAAAAAAAAAA`,
        });
        expect(response.statusCode).toBe(404);
    });
});

describe("delivery webhooks", () => {
    const deliveryEvent = (type: string, extra: Record<string, unknown> = {}) => ({
        type,
        created_at: new Date().toISOString(),
        data: {
            email_id: `re_${sent.message.id}`,
            message_id: "resend-generated@eu-west-1.amazonses.com",
            tags: { message: sent.message.id },
            ...extra,
        },
    });

    async function message() {
        const response: SyncResponse = expectStatus(
            await harness.app.inject({ method: "GET", url: "/sync", headers }),
            200,
        );
        return response.messages.find((candidate) => candidate.id === sent.message.id);
    }

    it("learns the Message-ID from email.sent and the outcome from later events", async () => {
        await harness.webhook(deliveryEvent("email.sent"));
        await harness.webhook(deliveryEvent("email.delivered"));
        expect(await message()).toMatchObject({
            deliveryStatus: "delivered",
            messageIdHeader: "<resend-generated@eu-west-1.amazonses.com>",
        });
    });

    it("never moves a status backwards when webhooks arrive out of order", async () => {
        await harness.webhook(deliveryEvent("email.delivered"));
        await harness.webhook(deliveryEvent("email.delivery_delayed"));
        expect((await message())?.deliveryStatus).toBe("delivered");
    });

    it("records a bounce with its reason, once per webhook delivery", async () => {
        const bounce = deliveryEvent("email.bounced", {
            bounce: { message: "Mailbox does not exist", type: "Permanent", subType: "General" },
        });
        await harness.webhook(bounce, "msg_1");
        await harness.webhook(bounce, "msg_1");
        const response: SyncResponse = expectStatus(
            await harness.app.inject({ method: "GET", url: "/sync", headers }),
            200,
        );
        expect(response.events.filter((event) => event.type === "bounced")).toEqual([
            expect.objectContaining({ detail: "Mailbox does not exist" }),
        ]);
    });
});
