import { claimInputSchema, claimSchema, errorSchema } from "@repo/contracts";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

/** Public. The only route a device without the owner token can use to get one. */
export const ownerRoutes: FastifyPluginAsyncZod = async (app) => {
    app.post(
        "/claim",
        {
            schema: {
                operationId: "claim",
                body: claimInputSchema,
                response: { 200: claimSchema, 400: errorSchema, 409: errorSchema },
            },
        },
        (request) => app.owner.claim(request.body.code).then((token) => ({ token })),
    );
};
