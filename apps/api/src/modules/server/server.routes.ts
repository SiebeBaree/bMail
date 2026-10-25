import { errorSchema, serverStatusSchema, setResendKeySchema } from "@repo/contracts";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

import { serverService } from "./server.service";

export const serverRoutes: FastifyPluginAsyncZod = async (app) => {
    const service = serverService({ settings: app.settings, resend: app.resend, publicUrl: app.publicUrl });

    app.get("/server", { schema: { operationId: "serverStatus", response: { 200: serverStatusSchema } } }, () =>
        service.status(),
    );

    app.put(
        "/server/resend",
        {
            schema: {
                operationId: "setResendKey",
                body: setResendKeySchema,
                response: { 200: serverStatusSchema, 400: errorSchema, 502: errorSchema },
            },
        },
        (request) => service.setResendKey(request.body.apiKey),
    );
};
