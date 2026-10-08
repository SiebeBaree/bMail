import type { FastifyRequest } from "fastify";
import fp from "fastify-plugin";

const REQUEST_ID_PATTERN = /^[\w-]{1,64}$/;

// Accepts the caller's x-request-id (the web client sends one per call) so one id spans browser, api log line and
// Sentry event. Anything not matching the pattern is replaced to keep hostile input out of logs.
export function genReqId(request: Pick<FastifyRequest, "headers">) {
    const inbound = request.headers["x-request-id"];
    return typeof inbound === "string" && REQUEST_ID_PATTERN.test(inbound) ? inbound : crypto.randomUUID();
}

export const requestIdPlugin = fp(async (app) => {
    app.addHook("onSend", async (request, reply) => {
        reply.header("x-request-id", request.id);
    });
});
