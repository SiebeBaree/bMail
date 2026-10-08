import { afterAll, beforeAll, expect, it } from "vitest";

import { buildTestApp } from "../../test/build-app";

let harness: Awaited<ReturnType<typeof buildTestApp>>;

beforeAll(async () => {
    harness = await buildTestApp();
});
afterAll(() => harness.close());

it("GET /health reports ok", async () => {
    const response = await harness.app.inject({ method: "GET", url: "/health" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ok" });
});
