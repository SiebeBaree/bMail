import {
    createDomainSchema,
    domainListSchema,
    domainSchema,
    errorSchema,
    idParamSchema,
    updateDomainSchema,
} from "@repo/contracts";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { z } from "zod";

import { domainsService } from "./domains.service";

export const domainsRoutes: FastifyPluginAsyncZod = async (app) => {
    const service = domainsService({ db: app.db, resend: app.resend, publicUrl: app.publicUrl });

    app.get("/domains", { schema: { operationId: "listDomains", response: { 200: domainListSchema } } }, (request) =>
        service.list(request.userId),
    );

    app.post(
        "/domains",
        {
            schema: {
                operationId: "createDomain",
                body: createDomainSchema,
                response: { 201: domainSchema, 400: errorSchema, 409: errorSchema, 502: errorSchema },
            },
        },
        async (request, reply) => reply.status(201).send(await service.create(request.userId, request.body.name)),
    );

    app.post(
        "/domains/:id/verify",
        {
            schema: {
                operationId: "verifyDomain",
                params: idParamSchema,
                response: { 200: domainSchema, 404: errorSchema, 502: errorSchema },
            },
        },
        (request) => service.verify(request.userId, request.params.id),
    );

    app.patch(
        "/domains/:id",
        {
            schema: {
                operationId: "updateDomain",
                params: idParamSchema,
                body: updateDomainSchema,
                response: { 200: domainSchema, 400: errorSchema, 404: errorSchema },
            },
        },
        (request) => service.update(request.userId, request.params.id, request.body),
    );

    // Its own route because the generated Swift client leaves nil fields out, so a PATCH can't carry a null.
    app.delete(
        "/domains/:id/catch-all",
        {
            schema: {
                operationId: "clearCatchAll",
                params: idParamSchema,
                response: { 200: domainSchema, 404: errorSchema },
            },
        },
        (request) => service.update(request.userId, request.params.id, { catchAllMailboxId: null }),
    );

    app.delete(
        "/domains/:id",
        {
            schema: {
                operationId: "deleteDomain",
                params: idParamSchema,
                response: { 204: z.null(), 404: errorSchema, 502: errorSchema },
            },
        },
        async (request, reply) => {
            await service.remove(request.userId, request.params.id);
            return reply.status(204).send(null);
        },
    );
};
