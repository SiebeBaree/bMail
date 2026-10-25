import type { ServerStatus } from "@repo/contracts";

import type { ResendGateway } from "../../lib/resend";
import type { ServerSettings } from "../../lib/server-settings";

type Dependencies = { settings: ServerSettings; resend: ResendGateway; publicUrl: string };

/** The server's own setup, as bMail's Settings shows it. */
export function serverService({ settings, resend, publicUrl }: Dependencies) {
    async function status(): Promise<ServerStatus> {
        return { publicUrl, resend: (await settings.resend()) !== null };
    }

    return {
        status,

        /**
         * Saves a Resend key once Resend has accepted it, which it proves by creating the webhook this server needs.
         * A webhook made for an earlier key goes, so Resend doesn't deliver every event twice.
         */
        async setResendKey(apiKey: string): Promise<ServerStatus> {
            const webhook = await resend.createWebhook(apiKey, `${publicUrl}/webhooks/resend`);
            const previous = await settings.savedWebhook();
            await settings.saveResend({ apiKey, webhookId: webhook.id, webhookSecret: webhook.signingSecret });
            // Best effort: the old key may be revoked already, and a leftover webhook only costs a rejected delivery.
            if (previous && previous.id !== webhook.id)
                await resend.removeWebhook(previous.apiKey, previous.id).catch(() => {});
            return status();
        },
    };
}
