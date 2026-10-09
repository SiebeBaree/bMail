import { z } from "zod";

import { trackedLinkSchema } from "./messages";

/** Html the app is about to send from Gmail, to be instrumented for tracking. */
export const trackMessageSchema = z
    .object({
        /** The app's id for the message. A retry with the same id returns the same html. */
        id: z.uuid(),
        html: z.string().max(2_000_000),
    })
    .meta({ id: "TrackMessage" });

/** What the app sends instead of the html it wrote. */
export const trackedHtmlSchema = z
    .object({
        html: z.string(),
    })
    .meta({ id: "TrackedHtml" });

/** A Gmail message the api tracks. Its opens and clicks arrive as events with this id as `messageId`. */
export const trackedMessageSchema = z
    .object({
        id: z.uuid(),
        links: z.array(trackedLinkSchema),
    })
    .meta({ id: "TrackedMessage" });

export type TrackMessageInput = z.infer<typeof trackMessageSchema>;
export type TrackedHtml = z.infer<typeof trackedHtmlSchema>;
export type TrackedMessage = z.infer<typeof trackedMessageSchema>;
