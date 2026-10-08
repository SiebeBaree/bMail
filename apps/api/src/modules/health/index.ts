import { healthSchema } from "@repo/contracts";
import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";

export const healthModule: FastifyPluginAsyncZod = async (app) => {
    app.get("/health", { schema: { response: { 200: healthSchema } } }, async () => ({ status: "ok" as const }));
};
