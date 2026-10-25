import { afterAll, beforeAll, beforeEach, expect, it } from "vitest";

import { buildTestApp, expectStatus, PUBLIC_URL, type TestHarness } from "../../test/build-app";
import { REJECTED_KEY } from "../../test/fake-resend";

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

const setKey = (apiKey: string) =>
    harness.app.inject({ method: "PUT", url: "/server/resend", headers, payload: { apiKey } });

it("says Resend isn't set up on a fresh server", async () => {
    const status = expectStatus(await harness.app.inject({ method: "GET", url: "/server", headers }), 200);

    expect(status).toEqual({ publicUrl: PUBLIC_URL, resend: false });
});

it("saves a Resend key by creating the webhook it needs", async () => {
    const status = expectStatus(await setKey("re_first"), 200);

    expect(status.resend).toBe(true);
    expect(harness.resend.webhooks).toEqual([
        { id: "wh_1", apiKey: "re_first", endpoint: `${PUBLIC_URL}/webhooks/resend`, signingSecret: "whsec_1" },
    ]);
});

it("removes the old webhook when the key is replaced", async () => {
    expectStatus(await setKey("re_first"), 200);
    expectStatus(await setKey("re_second"), 200);

    expect(harness.resend.webhooks.map((webhook) => webhook.apiKey)).toEqual(["re_second"]);
});

it("keeps nothing when Resend refuses the key", async () => {
    const response = await setKey(REJECTED_KEY);

    expect(response.statusCode).toBe(400);
    expect(response.json().message).toBe("Resend didn't accept that key. Use a full access key.");
    const status = expectStatus(await harness.app.inject({ method: "GET", url: "/server", headers }), 200);
    expect(status.resend).toBe(false);
});

it("keeps the tracking secret it generated", async () => {
    const first = await harness.app.settings.trackingSecret();

    expect(await harness.app.settings.trackingSecret()).toBe(first);
});
