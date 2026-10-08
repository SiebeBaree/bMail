import { z } from "zod";

import { eventSources, eventTypes } from "./vocabulary";

export const messageEventSchema = z
    .object({
        id: z.uuid(),
        messageId: z.uuid(),
        type: z.enum(eventTypes),
        source: z.enum(eventSources).nullable(),
        url: z.string().nullable(),
        device: z.string().nullable(),
        city: z.string().nullable(),
        country: z.string().nullable(),
        detail: z.string().nullable(),
        occurredAt: z.iso.datetime(),
    })
    .meta({ id: "MessageEvent" });

export const trackingTokenParamSchema = z.object({
    token: z.string().max(200),
});

export type MessageEvent = z.infer<typeof messageEventSchema>;
