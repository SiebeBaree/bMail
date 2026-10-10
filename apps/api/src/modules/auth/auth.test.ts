import { users } from "@repo/db";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { setPassword } from "../../auth";
import { buildTestApp, OWNER, type TestHarness } from "../../test/build-app";

let harness: TestHarness;

beforeAll(async () => {
    harness = await buildTestApp();
});
afterAll(() => harness.close());
beforeEach(() => harness.reset());

describe("accounts", () => {
    it("can't be created by a password sign-up, even for an allowlisted email", async () => {
        const response = await harness.app.inject({
            method: "POST",
            url: "/api/auth/sign-up/email",
            payload: { ...OWNER, name: "Not Siebe" },
        });
        expect(response.statusCode).toBe(400);
        expect(await harness.db.select().from(users)).toEqual([]);
    });

    it("only exist for allowlisted emails", async () => {
        await expect(setPassword(harness.auth, "stranger@example.com", "a long password")).rejects.toThrow(
            "ALLOWED_EMAILS",
        );
    });

    it("sign in with the password set on the server and use the session as a bearer token", async () => {
        const headers = await harness.signIn();
        const response = await harness.app.inject({ method: "GET", url: "/sync", headers });
        expect(response.statusCode).toBe(200);
    });

    it("are signed out everywhere when the password is set again", async () => {
        const headers = await harness.signIn();
        await setPassword(harness.auth, OWNER.email, "a brand new password");
        expect((await harness.app.inject({ method: "GET", url: "/sync", headers })).statusCode).toBe(401);
        const old = await harness.app.inject({ method: "POST", url: "/api/auth/sign-in/email", payload: OWNER });
        expect(old.statusCode).toBe(401);
    });

    it("are shut out while their email is unverified, like one an old password sign-up made", async () => {
        const headers = await harness.signIn();
        await harness.db.update(users).set({ emailVerified: false });
        expect((await harness.app.inject({ method: "GET", url: "/sync", headers })).statusCode).toBe(401);
        const again = await harness.app.inject({ method: "POST", url: "/api/auth/sign-in/email", payload: OWNER });
        expect(again.statusCode).toBe(403);
    });
});

describe("private routes", () => {
    it("answer 401 without a session", async () => {
        const response = await harness.app.inject({ method: "GET", url: "/sync" });
        expect(response.statusCode).toBe(401);
        expect(response.json().message).toBe("Sign in again to continue.");
    });

    it("answer 401 for a made-up token", async () => {
        const response = await harness.app.inject({
            method: "GET",
            url: "/domains",
            headers: { authorization: "Bearer nope" },
        });
        expect(response.statusCode).toBe(401);
    });
});
