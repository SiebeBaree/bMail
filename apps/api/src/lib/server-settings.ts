import { randomBytes } from "node:crypto";

import { serverSettings, type Database } from "@repo/db";
import { sql } from "drizzle-orm";

export type ResendConfig = { apiKey: string; webhookSecret: string };

/**
 * The one row of server_settings: what the server generated for itself and the Resend key bMail sent it. Read on every
 * call that needs it, because serverless instances share nothing but the database.
 */
export function createServerSettings(db: Database, environment: { resend?: ResendConfig } = {}) {
    async function row() {
        const [settings] = await db.select().from(serverSettings).limit(1);
        return settings;
    }

    return {
        /** The key saved from bMail, else the one in the host's environment, else none. */
        async resend(): Promise<ResendConfig | null> {
            const settings = await row();
            if (settings?.resendApiKey && settings.resendWebhookSecret) {
                return { apiKey: settings.resendApiKey, webhookSecret: settings.resendWebhookSecret };
            }
            return environment.resend ?? null;
        },

        /** The webhook this server created for itself, so replacing the key can remove it. */
        async savedWebhook(): Promise<{ apiKey: string; id: string } | null> {
            const settings = await row();
            return settings?.resendApiKey && settings.resendWebhookId
                ? { apiKey: settings.resendApiKey, id: settings.resendWebhookId }
                : null;
        },

        async saveResend(config: ResendConfig & { webhookId: string }) {
            const values = {
                resendApiKey: config.apiKey,
                resendWebhookId: config.webhookId,
                resendWebhookSecret: config.webhookSecret,
            };
            await db
                .insert(serverSettings)
                .values({ id: 1, ...values })
                .onConflictDoUpdate({ target: serverSettings.id, set: values });
        },

        /**
         * Generated on first use and kept. Concurrent first boots race to insert and every one of them reads back the
         * winner's secret, because a tracking token signed with any other would never verify.
         */
        async trackingSecret(): Promise<string> {
            const [settings] = await db
                .insert(serverSettings)
                .values({ id: 1, trackingSecret: randomBytes(32).toString("base64url") })
                .onConflictDoUpdate({
                    target: serverSettings.id,
                    set: { trackingSecret: sql`coalesce(${serverSettings.trackingSecret}, excluded.tracking_secret)` },
                })
                .returning({ trackingSecret: serverSettings.trackingSecret });
            if (!settings?.trackingSecret) throw new Error("The tracking secret couldn't be saved.");
            return settings.trackingSecret;
        },
    };
}

export type ServerSettings = ReturnType<typeof createServerSettings>;
