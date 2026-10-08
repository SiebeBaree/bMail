import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { buildTestApp, OWNER, type TestHarness } from "../../test/build-app";

let harness: TestHarness;

beforeAll(async () => {
    harness = await buildTestApp();
});
afterAll(() => harness.close());
beforeEach(() => harness.reset());

describe("sign-in", () => {
    it("lets an allowlisted email sign up and use the session as a bearer token", async () => {
        const headers = await harness.signIn();
        const response = await harness.app.inject({ method: "GET", url: "/sync", headers });
        expect(response.statusCode).toBe(200);
    });

    it("refuses an email that isn't on the allowlist", async () => {
        const response = await harness.app.inject({
            method: "POST",
            url: "/api/auth/sign-up/email",
            payload: { ...OWNER, email: "stranger@example.com" },
        });
        expect(response.statusCode).toBe(403);
        expect(response.headers["set-auth-token"]).toBeUndefined();
    });

    it("signs in again with the same password", async () => {
        await harness.signIn();
        const response = await harness.app.inject({
            method: "POST",
            url: "/api/auth/sign-in/email",
            payload: { email: OWNER.email, password: OWNER.password },
        });
        expect(response.statusCode).toBe(200);
        expect(typeof response.headers["set-auth-token"]).toBe("string");
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
