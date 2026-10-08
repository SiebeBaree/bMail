import type { onRequestAsyncHookHandler } from "fastify";

import { toFetchHeaders } from "../lib/headers";

declare module "fastify" {
    interface FastifyRequest {
        /** Set by `authenticate` on every route in the private scope of app.ts. */
        userId: string;
    }
}

/** Resolves the bearer token to a Better Auth session. Everything after this hook can trust `request.userId`. */
export const authenticate: onRequestAsyncHookHandler = async function (request, reply) {
    const session = await this.auth.api.getSession({ headers: toFetchHeaders(request.headers) });
    if (!session) {
        return reply.status(401).send({ message: "Sign in again to continue.", requestId: request.id });
    }
    request.userId = session.user.id;
};
