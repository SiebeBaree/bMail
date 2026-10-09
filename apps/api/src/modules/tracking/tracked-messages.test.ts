import type { SyncResponse, TrackedHtml } from "@repo/contracts";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import { buildTestApp, expectStatus, type TestHarness } from "../../test/build-app";

let harness: TestHarness;
let headers: { authorization: string };

beforeAll(async () => {
    harness = await buildTestApp();
});
afterAll(() => harness.close());
beforeEach(async () => {
    vi.useRealTimers();
    await harness.reset();
    headers = await harness.signIn();
});

const html = '<p>Here is <a href="https://baree.be/proposal">the proposal</a>.</p>';
const track = (id: string) =>
    harness.app.inject({ method: "POST", url: "/tracking/messages", headers, payload: { id, html } });
const pathOf = (tracked: TrackedHtml, pattern: RegExp) => new URL(pattern.exec(tracked.html)?.[1] ?? "").pathname;
const pixelPath = (tracked: TrackedHtml) => pathOf(tracked, /<img src="([^"]+)"/);
const clickPath = (tracked: TrackedHtml) => pathOf(tracked, /href="([^"]+\/c\/[^"]+)"/);
const aMinuteLater = () => vi.useFakeTimers({ now: Date.now() + 60_000, toFake: ["Date"] });
const mac = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0) AppleWebKit/605.1.15 (KHTML, like Gecko)";

async function sync(): Promise<SyncResponse> {
    return expectStatus(await harness.app.inject({ method: "GET", url: "/sync", headers }), 200);
}

describe("POST /tracking/messages", () => {
    it("tracks a Gmail message through the api's host and syncs its opens under the app's id", async () => {
        const id = crypto.randomUUID();
        const tracked: TrackedHtml = expectStatus(await track(id), 200);
        expect(tracked.html).toMatch(/<img src="http:\/\/api\.test\/o\//);

        aMinuteLater();
        await harness.app.inject({ method: "GET", url: pixelPath(tracked), headers: { "user-agent": mac } });

        const { trackedMessages, events, messages } = await sync();
        expect(trackedMessages).toEqual([
            { id, links: [{ id: expect.any(String), url: "https://baree.be/proposal" }] },
        ]);
        expect(events).toEqual([expect.objectContaining({ messageId: id, type: "opened", source: "person" })]);
        expect(messages).toEqual([]);
    });

    it("returns the same html for a retry and stores nothing new", async () => {
        const id = crypto.randomUUID();
        const first: TrackedHtml = expectStatus(await track(id), 200);
        const retry: TrackedHtml = expectStatus(await track(id), 200);
        expect(retry.html).toBe(first.html);
        expect((await sync()).trackedMessages).toEqual([expect.objectContaining({ id, links: [expect.anything()] })]);
    });

    it("redirects a click to the original link and records it", async () => {
        const id = crypto.randomUUID();
        const tracked: TrackedHtml = expectStatus(await track(id), 200);

        aMinuteLater();
        const response = await harness.app.inject({
            method: "GET",
            url: clickPath(tracked),
            headers: { "user-agent": mac },
        });
        expect(response.statusCode).toBe(302);
        expect(response.headers.location).toBe("https://baree.be/proposal");
        expect((await sync()).events).toEqual([
            expect.objectContaining({ messageId: id, type: "clicked", url: "https://baree.be/proposal" }),
        ]);
    });

    it("refuses the id of a message sent through a domain", async () => {
        const { mailboxId } = await harness.seedMailbox(headers);
        const id = crypto.randomUUID();
        expectStatus(
            await harness.app.inject({
                method: "POST",
                url: "/messages",
                headers,
                payload: {
                    id,
                    conversationId: crypto.randomUUID(),
                    mailboxId,
                    to: [{ email: "jan@wouters.example" }],
                    subject: "Proposal for Q4",
                    html,
                    text: "Here is the proposal.",
                },
            }),
            200,
        );
        expect((await track(id)).statusCode).toBe(409);
    });
});
