import type { FastifyPluginAsync } from "fastify";

import { toFetchHeaders } from "../../lib/headers";

/** Hands /api/auth/* to Better Auth, translating between Fastify's request and the Fetch api it speaks. */
export const authModule: FastifyPluginAsync = async (app) => {
    app.route({
        method: ["GET", "POST"],
        url: "/api/auth/*",
        schema: { hide: true },
        async handler(request, reply) {
            const headers = toFetchHeaders(request.headers);
            // The body is re-serialized below, so the original length no longer applies.
            headers.delete("content-length");
            const response = await app.auth.handler(
                new Request(new URL(request.url, app.publicUrl), {
                    method: request.method,
                    headers,
                    ...(request.body === undefined ? {} : { body: JSON.stringify(request.body) }),
                }),
            );

            reply.status(response.status);
            response.headers.forEach((value, key) => {
                if (key !== "set-cookie") reply.header(key, value);
            });
            const cookies = response.headers.getSetCookie();
            if (cookies.length > 0) reply.header("set-cookie", cookies);
            return reply.send(response.body ? await response.text() : null);
        },
    });
};
