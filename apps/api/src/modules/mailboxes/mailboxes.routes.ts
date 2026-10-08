import { createMailboxSchema, errorSchema, idParamSchema, mailboxSchema, updateMailboxSchema } from "@repo/contracts";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { z } from "zod";

import { mailboxesService } from "./mailboxes.service";

export const mailboxesRoutes: FastifyPluginAsyncZod = async (app) => {
    const service = mailboxesService(app.db);

    app.post(
        "/mailboxes",
        {
            schema: {
                operationId: "createMailbox",
                body: createMailboxSchema,
                response: { 201: mailboxSchema, 400: errorSchema, 404: errorSchema, 409: errorSchema },
            },
        },
        async (request, reply) => reply.status(201).send(await service.create(request.userId, request.body)),
    );

    app.patch(
        "/mailboxes/:id",
        {
            schema: {
                operationId: "updateMailbox",
                params: idParamSchema,
                body: updateMailboxSchema,
                response: { 200: mailboxSchema, 400: errorSchema, 404: errorSchema },
            },
        },
        (request) => service.update(request.userId, request.params.id, request.body),
    );

    app.delete(
        "/mailboxes/:id",
        {
            schema: {
                operationId: "deleteMailbox",
                params: idParamSchema,
                response: { 204: z.null(), 404: errorSchema },
            },
        },
        async (request, reply) => {
            await service.remove(request.userId, request.params.id);
            return reply.status(204).send(null);
        },
    );
};
