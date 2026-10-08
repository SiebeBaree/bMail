import { syncQuerySchema, syncResponseSchema } from "@repo/contracts";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

import { syncService } from "./sync.service";

export const syncRoutes: FastifyPluginAsyncZod = async (app) => {
    const service = syncService(app.db);

    app.get(
        "/sync",
        { schema: { operationId: "sync", querystring: syncQuerySchema, response: { 200: syncResponseSchema } } },
        (request) => service.changes(request.userId, request.query.cursor, request.query.limit),
    );
};
