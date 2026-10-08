import {
    attachmentUrlSchema,
    createUploadSchema,
    errorSchema,
    idParamSchema,
    sendMessageSchema,
    sentMessageSchema,
    uploadSchema,
} from "@repo/contracts";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

import { sendService } from "./send.service";

export const messagesRoutes: FastifyPluginAsyncZod = async (app) => {
    const service = sendService({
        db: app.db,
        resend: app.resend,
        storage: app.storage,
        trackingTokens: app.trackingTokens,
        publicUrl: app.publicUrl,
    });

    app.post(
        "/messages",
        {
            // Html can be large (forwarded newsletters); attachments never pass through here, see /uploads.
            bodyLimit: 4 * 1024 * 1024,
            schema: {
                operationId: "sendMessage",
                body: sendMessageSchema,
                response: {
                    200: sentMessageSchema,
                    400: errorSchema,
                    404: errorSchema,
                    409: errorSchema,
                    502: errorSchema,
                },
            },
        },
        (request) => service.send(request.userId, request.body),
    );

    app.post(
        "/uploads",
        {
            schema: {
                operationId: "createUpload",
                body: createUploadSchema,
                response: { 201: uploadSchema, 400: errorSchema },
            },
        },
        async (request, reply) => reply.status(201).send(await service.createUpload(request.userId, request.body)),
    );

    app.get(
        "/attachments/:id/url",
        {
            schema: {
                operationId: "getAttachmentUrl",
                params: idParamSchema,
                response: { 200: attachmentUrlSchema, 404: errorSchema },
            },
        },
        (request) => service.attachmentUrl(request.userId, request.params.id),
    );
};
