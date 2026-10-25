import { ownerTokens } from "@repo/db";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { buildTestApp, CLAIM_CODE, expectStatus, type TestHarness } from "../../test/build-app";
import { hashToken } from "./owner.service";

let harness: TestHarness;

beforeAll(async () => {
    harness = await buildTestApp();
});
afterAll(() => harness.close());
beforeEach(() => harness.reset());

const claim = (payload: { code?: string } = {}) => harness.app.inject({ method: "POST", url: "/claim", payload });
const sync = (authorization: string) =>
    harness.app.inject({ method: "GET", url: "/sync?cursor=0", headers: { authorization } });
const health = async () => expectStatus(await harness.app.inject({ method: "GET", url: "/health" }), 200);

describe("POST /claim", () => {
    it("gives the first device the owner token", async () => {
        expect(await health()).toEqual({ status: "ok", claimed: false });

        const { token } = expectStatus(await claim(), 200);

        expect((await sync(`Bearer ${token}`)).statusCode).toBe(200);
        expect(await health()).toEqual({ status: "ok", claimed: true });
    });

    it("turns away everyone after that", async () => {
        await harness.claim();

        const second = await claim();

        expect(second.statusCode).toBe(409);
        expect(second.json().message).toMatch(/already has an owner/);
    });

    it("refuses a wrong claim code", async () => {
        await harness.claim();

        const wrong = await claim({ code: "not-the-code" });

        expect(wrong.statusCode).toBe(409);
        expect(wrong.json().message).toBe("That claim code doesn't match.");
    });

    it("hands the server back with the claim code and signs out every other device", async () => {
        const old = await harness.claim();
        await harness.seedMailbox(old);

        const { token } = expectStatus(await claim({ code: CLAIM_CODE }), 200);

        expect((await sync(old.authorization)).statusCode).toBe(401);
        const synced = expectStatus(await sync(`Bearer ${token}`), 200);
        expect(synced.domains).toHaveLength(1);
    });
});

describe("the owner token", () => {
    it("is required on private routes", async () => {
        await harness.claim();

        const response = await sync("Bearer not-a-token");

        expect(response.statusCode).toBe(401);
        expect(response.json().message).toBe("Connect this device to your server again.");
    });

    it("still works in the form Better Auth handed out before the claim existed", async () => {
        const { authorization } = await harness.claim();
        const [row] = await harness.db.select().from(ownerTokens);
        if (!row) throw new Error("no owner token");
        // What the migration does with a live session: keep the hash of its token.
        await harness.db.insert(ownerTokens).values({ tokenHash: hashToken("sessiontoken"), userId: row.userId });

        expect((await sync(authorization)).statusCode).toBe(200);
        expect((await sync("Bearer sessiontoken.c2lnbmF0dXJl%3D")).statusCode).toBe(200);
    });
});
