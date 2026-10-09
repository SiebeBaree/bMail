import {
    conversationLabelsSchema,
    createLabelSchema,
    errorSchema,
    idParamSchema,
    labelSchema,
    setConversationLabelsSchema,
    updateLabelSchema,
} from "@repo/contracts";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { z } from "zod";

import { labelsService } from "./labels.service";

export const labelsRoutes: FastifyPluginAsyncZod = async (app) => {
    const service = labelsService(app.db);

    app.post(
        "/labels",
        {
            schema: {
                operationId: "createLabel",
                body: createLabelSchema,
                response: { 201: labelSchema, 400: errorSchema, 409: errorSchema },
            },
        },
        async (request, reply) => reply.status(201).send(await service.create(request.userId, request.body)),
    );

    app.patch(
        "/labels/:id",
        {
            schema: {
                operationId: "updateLabel",
                params: idParamSchema,
                body: updateLabelSchema,
                response: { 200: labelSchema, 400: errorSchema, 404: errorSchema, 409: errorSchema },
            },
        },
        (request) => service.update(request.userId, request.params.id, request.body),
    );

    app.delete(
        "/labels/:id",
        {
            schema: {
                operationId: "deleteLabel",
                params: idParamSchema,
                response: { 204: z.null(), 404: errorSchema },
            },
        },
        async (request, reply) => {
            await service.remove(request.userId, request.params.id);
            return reply.status(204).send(null);
        },
    );

    app.put(
        "/conversations/:id/labels",
        {
            schema: {
                operationId: "setConversationLabels",
                params: idParamSchema,
                body: setConversationLabelsSchema,
                response: { 200: conversationLabelsSchema, 400: errorSchema, 404: errorSchema },
            },
        },
        (request) => service.setConversationLabels(request.userId, request.params.id, request.body.labelIds),
    );
};
