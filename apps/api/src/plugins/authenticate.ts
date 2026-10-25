import type { onRequestAsyncHookHandler } from "fastify";

declare module "fastify" {
    interface FastifyRequest {
        /** Set by `authenticate` on every route in the private scope of app.ts. */
        userId: string;
    }
}

/** Resolves the owner token to its owner. Everything after this hook can trust `request.userId`. */
export const authenticate: onRequestAsyncHookHandler = async function (request, reply) {
    const header = request.headers.authorization ?? "";
    const bearer = header.toLowerCase().startsWith("bearer ") ? header.slice(7).trim() : "";
    const userId = bearer ? await this.owner.userIdFor(bearer) : null;
    if (!userId) {
        return reply.status(401).send({ message: "Connect this device to your server again.", requestId: request.id });
    }
    request.userId = userId;
};
