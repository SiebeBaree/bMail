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

const createDomain = (name: string) =>
    harness.app.inject({ method: "POST", url: "/domains", headers, payload: { name } });

describe("POST /domains", () => {
    it("adds the domain in Resend and lists Resend's records plus tracking and DMARC", async () => {
        const domain = expectStatus(await createDomain("  Baree.TEST "), 201);
        expect(domain).toMatchObject({
            name: "baree.test",
            status: "pending",
            trackingHost: "t.baree.test",
            trackingHostVerified: false,
        });
        expect(domain.records.map((record: { purpose: string }) => record.purpose)).toEqual([
            "dkim",
            "spf",
            "receiving",
            "tracking",
            "dmarc",
        ]);
        expect(domain.records.find((record: { purpose: string }) => record.purpose === "tracking")).toMatchObject({
            type: "CNAME",
            name: "t",
            value: "api.test",
        });
    });

    it("refuses a domain that is already added", async () => {
        await createDomain("baree.test");
        const response = await createDomain("baree.test");
        expect(response.statusCode).toBe(409);
        expect(response.json().message).toBe("baree.test is already added.");
    });

    it("rejects something that isn't a domain", async () => {
        const response = await createDomain("not a domain");
        expect(response.statusCode).toBe(400);
        expect(response.json().issues).toEqual([{ path: "name", message: "Enter a domain like baree.be." }]);
    });

    it("can add a domain again after removing it", async () => {
        const domain = expectStatus(await createDomain("baree.test"), 201);
        expectStatus(await harness.app.inject({ method: "DELETE", url: `/domains/${domain.id}`, headers }), 204);
        expect((await createDomain("baree.test")).statusCode).toBe(201);
    });
});

describe("POST /domains/:id/verify", () => {
    it("picks up the status Resend reports", async () => {
        const domain = expectStatus(await createDomain("baree.test"), 201);
        harness.resend.verifyDomain("baree.test");
        const verified = expectStatus(
            await harness.app.inject({ method: "POST", url: `/domains/${domain.id}/verify`, headers }),
            200,
        );
        expect(verified.status).toBe("verified");
        expect(verified.records.filter((record: { status: string }) => record.status === "verified")).toHaveLength(3);
    });
});

describe("mailboxes", () => {
    it("makes the first mailbox of a domain its catch-all", async () => {
        const { domainId, mailboxId } = await harness.seedMailbox(headers);
        const [domain] = expectStatus(await harness.app.inject({ method: "GET", url: "/domains", headers }), 200);
        expect(domain).toMatchObject({ id: domainId, catchAllMailboxId: mailboxId });
    });

    it("turns the catch-all off", async () => {
        const { domainId } = await harness.seedMailbox(headers);
        const domain = expectStatus(
            await harness.app.inject({ method: "DELETE", url: `/domains/${domainId}/catch-all`, headers }),
            200,
        );
        expect(domain).toMatchObject({ id: domainId, catchAllMailboxId: null });
    });

    it("refuses a second mailbox with the same address", async () => {
        const { domainId } = await harness.seedMailbox(headers);
        const response = await harness.app.inject({
            method: "POST",
            url: "/mailboxes",
            headers,
            payload: { id: crypto.randomUUID(), domainId, localPart: "Siebe", displayName: "Again" },
        });
        expect(response.statusCode).toBe(409);
        expect(response.json().message).toBe("siebe@baree.test already exists.");
    });
});
