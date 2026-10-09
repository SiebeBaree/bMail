import { randomUUID } from "node:crypto";

import type { TrackedHtml, TrackMessageInput } from "@repo/contracts";
import { links, messages, trackedMessages, type Database } from "@repo/db";
import { eq } from "drizzle-orm";

import { ConflictError } from "../../lib/errors";
import { instrumentHtml } from "../../lib/html";
import type { TrackingTokens } from "../../lib/tracking-token";
import { messagesRepo } from "../messages/messages.repo";

type Dependencies = { db: Database; trackingTokens: TrackingTokens; publicUrl: string };

export function trackedMessagesService({ db, trackingTokens, publicUrl }: Dependencies) {
    return {
        /**
         * Instruments html the app sends from Gmail or Outlook, through the api's own host since those senders have
         * no t.<domain>. A retry with the same id reuses the stored links in order, so it returns the same html and
         * stores nothing new.
         */
        async track(userId: string, input: TrackMessageInput): Promise<TrackedHtml> {
            const [[existing], [sent]] = await Promise.all([
                db.select().from(trackedMessages).where(eq(trackedMessages.id, input.id)),
                db.select({ id: messages.id }).from(messages).where(eq(messages.id, input.id)),
            ]);
            // Opens and clicks find their message by id alone, in both tables, so an id can only mean one message.
            if (sent || (existing && existing.userId !== userId)) {
                throw new ConflictError("That message id is already taken.");
            }

            const knownLinks = existing ? await messagesRepo(db).linksOf(existing.id) : [];
            const trackedLinks: { id: string; url: string }[] = [];
            const html = instrumentHtml(input.html, {
                pixelUrl: `${publicUrl}/o/${trackingTokens.create("open", input.id)}`,
                rewriteLink: (url) => {
                    const link = knownLinks[trackedLinks.length] ?? { id: randomUUID(), url };
                    trackedLinks.push(link);
                    return `${publicUrl}/c/${trackingTokens.create("click", link.id)}`;
                },
            });

            if (!existing) {
                await db.transaction(async (tx) => {
                    await tx.insert(trackedMessages).values({ id: input.id, userId, sentAt: new Date() });
                    if (trackedLinks.length > 0) {
                        await tx.insert(links).values(
                            trackedLinks.map((link, position) => ({
                                id: link.id,
                                url: link.url,
                                position,
                                messageId: input.id,
                            })),
                        );
                    }
                });
            }
            return { html };
        },
    };
}
