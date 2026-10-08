import { z } from "zod";

import { conversationSchema } from "./conversations";
import { domainSchema } from "./domains";
import { messageEventSchema } from "./events";
import { mailboxSchema } from "./mailboxes";
import { messageSchema } from "./messages";

export const syncQuerySchema = z.object({
    cursor: z.coerce.number().int().min(0).default(0),
    limit: z.coerce.number().int().min(1).max(500).default(200),
});

/**
 * Everything that changed after `cursor`, oldest first. The app stores the returned cursor and asks again while
 * `hasMore` is true. Deletions arrive as rows with `deletedAt` set.
 */
export const syncResponseSchema = z
    .object({
        cursor: z.number().int(),
        hasMore: z.boolean(),
        domains: z.array(domainSchema),
        mailboxes: z.array(mailboxSchema),
        conversations: z.array(conversationSchema),
        messages: z.array(messageSchema),
        events: z.array(messageEventSchema),
    })
    .meta({ id: "SyncResponse" });

export type SyncResponse = z.infer<typeof syncResponseSchema>;
