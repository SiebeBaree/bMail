import type { DeliveryStatus } from "@repo/contracts";
import { messages, webhookReceipts, type Database } from "@repo/db";
import { and, eq } from "drizzle-orm";
import type { WebhookEventPayload } from "resend";

import { normalizeMessageId } from "../../lib/headers";
import { messagesRepo } from "../messages/messages.repo";

type DeliveryEvent = Extract<
    WebhookEventPayload,
    {
        type:
            | "email.sent"
            | "email.delivered"
            | "email.delivery_delayed"
            | "email.bounced"
            | "email.complained"
            | "email.failed";
    }
>;

const STATUS: Record<DeliveryEvent["type"], Exclude<DeliveryStatus, "sending">> = {
    "email.sent": "sent",
    "email.delivered": "delivered",
    "email.delivery_delayed": "delayed",
    "email.bounced": "bounced",
    "email.complained": "complained",
    "email.failed": "failed",
};

// Webhooks arrive out of order. A status only moves forward, so a late `delayed` never undoes `delivered`.
const RANK: Record<DeliveryStatus, number> = {
    sending: 0,
    sent: 1,
    delayed: 2,
    delivered: 3,
    bounced: 4,
    complained: 4,
    failed: 4,
};

export function isDeliveryEvent(event: WebhookEventPayload): event is DeliveryEvent {
    return event.type in STATUS;
}

export function deliveryService(db: Database) {
    return {
        /** Records one delivery webhook. The receipt and the change commit together, so a retry is a no-op. */
        async record(svixId: string, event: DeliveryEvent): Promise<void> {
            await db.transaction(async (tx) => {
                const [fresh] = await tx.insert(webhookReceipts).values({ svixId }).onConflictDoNothing().returning();
                if (!fresh) return;

                const ourId = event.data.tags?.message;
                const [message] = await tx
                    .select()
                    .from(messages)
                    .where(
                        and(
                            eq(messages.direction, "outbound"),
                            ourId ? eq(messages.id, ourId) : eq(messages.resendEmailId, event.data.email_id),
                        ),
                    );
                // Mail sent from Resend's dashboard or another app on the same account.
                if (!message) return;

                const status = STATUS[event.type];
                const current = message.deliveryStatus ?? "sending";
                await tx
                    .update(messages)
                    .set({
                        deliveryStatus: RANK[status] >= RANK[current] ? status : current,
                        resendEmailId: message.resendEmailId ?? event.data.email_id,
                        messageIdHeader: message.messageIdHeader ?? normalizeMessageId(event.data.message_id),
                    })
                    .where(eq(messages.id, message.id));

                // `sent` is recorded by the send call itself, the moment Resend accepts the email.
                if (event.type === "email.sent") return;
                await messagesRepo(tx).recordEvent({
                    userId: message.userId,
                    messageId: message.id,
                    type: status,
                    detail: detailOf(event),
                    occurredAt: new Date(event.created_at),
                });
            });
        },
    };
}

function detailOf(event: DeliveryEvent): string | null {
    if (event.type === "email.bounced") return event.data.bounce.message;
    if (event.type === "email.failed") return event.data.failed.reason;
    return null;
}
