import { z } from "zod";

import { folders } from "./vocabulary";

export const conversationSchema = z
    .object({
        id: z.uuid(),
        mailboxId: z.uuid(),
        subject: z.string(),
        folder: z.enum(folders),
        isRead: z.boolean(),
        isStarred: z.boolean(),
        snoozedUntil: z.iso.datetime().nullable(),
        lastMessageAt: z.iso.datetime(),
        lastOutboundAt: z.iso.datetime().nullable(),
    })
    .meta({ id: "Conversation" });

export const updateConversationSchema = z
    .object({
        folder: z.enum(folders).optional(),
        isRead: z.boolean().optional(),
        isStarred: z.boolean().optional(),
        snoozedUntil: z.iso.datetime().nullable().optional(),
    })
    .refine((input) => Object.values(input).some((value) => value !== undefined), "Nothing to update.")
    .meta({ id: "UpdateConversation" });

export type Conversation = z.infer<typeof conversationSchema>;
export type UpdateConversationInput = z.infer<typeof updateConversationSchema>;
