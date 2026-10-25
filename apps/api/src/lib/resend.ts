import type { DnsRecord, Domain } from "@repo/contracts";
import { Resend, type WebhookEventPayload } from "resend";

import { BadRequestError, UpstreamError } from "./errors";
import type { ResendConfig } from "./server-settings";

// Resend sends from Ireland, closest to Belgium. Changing it means re-creating domains.
const REGION = "eu-west-1";

export type OutgoingEmail = {
    from: string;
    to: string[];
    cc: string[];
    bcc: string[];
    subject: string;
    html: string;
    text: string;
    headers: Record<string, string>;
    attachments: { filename: string; contentType: string; url: string }[];
    /** Comes back on every webhook for this email. */
    tags: Record<string, string>;
};

export type ReceivedEmail = {
    id: string;
    messageId: string;
    from: string;
    to: string[];
    cc: string[];
    bcc: string[];
    replyTo: string[];
    receivedFor: string[];
    subject: string;
    html: string | null;
    text: string | null;
    headers: Record<string, string>;
    createdAt: string;
    rawUrl: string | null;
};

export type ReceivedAttachment = {
    id: string;
    filename: string;
    contentType: string;
    size: number;
    contentId: string | null;
    downloadUrl: string;
};

export type ResendDomain = { id: string; status: Domain["status"]; records: DnsRecord[] };

/**
 * The slice of Resend this app uses, in our own types. Services depend on this, never on the SDK, which is what lets
 * tests swap in a fake.
 */
export type ResendGateway = {
    createDomain(name: string): Promise<ResendDomain>;
    getDomain(id: string): Promise<ResendDomain>;
    verifyDomain(id: string): Promise<void>;
    removeDomain(id: string): Promise<void>;
    send(email: OutgoingEmail, idempotencyKey: string): Promise<{ id: string }>;
    getReceivedEmail(id: string): Promise<ReceivedEmail>;
    listReceivedAttachments(emailId: string): Promise<ReceivedAttachment[]>;
    /** Throws when the signature doesn't match, or when Resend isn't set up yet. */
    verifyWebhook(payload: string, headers: Headers): Promise<WebhookEventPayload>;
    /**
     * Points a new webhook at this server with a key that isn't saved yet, which is also how a key gets checked.
     * Throws a BadRequestError when Resend refuses the key.
     */
    createWebhook(apiKey: string, endpoint: string): Promise<{ id: string; signingSecret: string }>;
    removeWebhook(apiKey: string, id: string): Promise<void>;
};

/** What Resend sends us. Delivery events feed tracking; email.received is inbound mail. */
const WEBHOOK_EVENTS = [
    "email.received",
    "email.sent",
    "email.delivered",
    "email.delivery_delayed",
    "email.bounced",
    "email.complained",
    "email.failed",
] as const;

/** `config` runs on every call: bMail can save a key while the server runs, on any instance. */
export function createResendGateway(config: () => Promise<ResendConfig | null>): ResendGateway {
    async function client() {
        const current = await config();
        if (!current) throw new UpstreamError("Resend isn't set up. Add your Resend API key in bMail's Settings.");
        return { resend: new Resend(current.apiKey), webhookSecret: current.webhookSecret };
    }

    async function getDomain(id: string): Promise<ResendDomain> {
        const { resend } = await client();
        const domain = await unwrap(resend.domains.get(id), "look up the domain");
        return { id: domain.id, status: domainStatus(domain.status), records: dnsRecords(domain.records) };
    }

    return {
        async createDomain(name) {
            const { resend } = await client();
            const capabilities = { sending: "enabled", receiving: "enabled" } as const;
            const { data: created, error } = await resend.domains.create({ name, region: REGION, capabilities });
            if (created) {
                return { id: created.id, status: domainStatus(created.status), records: dnsRecords(created.records) };
            }
            // A domain already in this Resend account (added by hand, or by an earlier try) is adopted, not refused.
            // Resend only says "registered already", which also covers a domain owned by another Resend account.
            const existing = (await unwrap(resend.domains.list(), "list domains")).data.find(
                (domain) => domain.name === name,
            );
            if (!existing) {
                throw new UpstreamError(`Resend couldn't add ${name}: ${error?.message ?? "empty response"}.`);
            }
            await unwrap(resend.domains.update({ id: existing.id, capabilities }), `turn on receiving for ${name}`);
            return getDomain(existing.id);
        },
        getDomain,
        async verifyDomain(id) {
            const { resend } = await client();
            await unwrap(resend.domains.verify(id), "start verification");
        },
        async removeDomain(id) {
            const { resend } = await client();
            await unwrap(resend.domains.remove(id), "remove the domain");
        },
        async send(email, idempotencyKey) {
            const { resend } = await client();
            return unwrap(
                resend.emails.send(
                    {
                        from: email.from,
                        to: email.to,
                        cc: email.cc,
                        bcc: email.bcc,
                        subject: email.subject,
                        html: email.html,
                        text: email.text,
                        headers: email.headers,
                        tags: Object.entries(email.tags).map(([name, value]) => ({ name, value })),
                        attachments: email.attachments.map((file) => ({
                            filename: file.filename,
                            path: file.url,
                            contentType: file.contentType,
                        })),
                    },
                    { idempotencyKey },
                ),
                "send the email",
            );
        },
        async getReceivedEmail(id) {
            const { resend } = await client();
            const email = await unwrap(resend.emails.receiving.get(id), "fetch the received email");
            return {
                id: email.id,
                messageId: email.message_id,
                from: email.from,
                to: email.to,
                cc: email.cc ?? [],
                bcc: email.bcc ?? [],
                replyTo: email.reply_to ?? [],
                receivedFor: email.received_for,
                subject: email.subject,
                html: email.html,
                text: email.text,
                headers: email.headers ?? {},
                createdAt: email.created_at,
                rawUrl: email.raw?.download_url ?? null,
            };
        },
        async listReceivedAttachments(emailId) {
            const { resend } = await client();
            const list = await unwrap(resend.emails.receiving.attachments.list({ emailId }), "list attachments");
            return list.data.map((file) => ({
                id: file.id,
                filename: file.filename ?? "attachment",
                contentType: file.content_type,
                size: file.size,
                contentId: file.content_id ?? null,
                downloadUrl: file.download_url,
            }));
        },
        async verifyWebhook(payload, headers) {
            const { resend, webhookSecret } = await client();
            return resend.webhooks.verify({
                payload,
                headers: {
                    id: headers.get("svix-id") ?? "",
                    timestamp: headers.get("svix-timestamp") ?? "",
                    signature: headers.get("svix-signature") ?? "",
                },
                webhookSecret,
            });
        },
        async createWebhook(apiKey, endpoint) {
            const { data, error } = await new Resend(apiKey).webhooks.create({ endpoint, events: [...WEBHOOK_EVENTS] });
            if (data) return { id: data.id, signingSecret: data.signing_secret };
            if (error?.statusCode === 401 || error?.statusCode === 403) {
                throw new BadRequestError("Resend didn't accept that key. Use a full access key.");
            }
            throw new UpstreamError(`Resend couldn't create the webhook: ${error?.message ?? "empty response"}.`);
        },
        async removeWebhook(apiKey, id) {
            await unwrap(new Resend(apiKey).webhooks.remove(id), "remove the old webhook");
        },
    };
}

// The SDK returns errors instead of throwing. This turns them into one error type the error handler knows.
async function unwrap<T>(call: Promise<{ data: T | null; error: { message: string } | null }>, action: string) {
    const { data, error } = await call;
    if (error || !data) throw new UpstreamError(`Resend couldn't ${action}: ${error?.message ?? "empty response"}.`);
    return data;
}

function domainStatus(status: string): Domain["status"] {
    if (status === "verified") return "verified";
    if (status === "failed" || status === "partially_failed") return "failed";
    return "pending";
}

const PURPOSES: Record<string, DnsRecord["purpose"] | undefined> = { SPF: "spf", DKIM: "dkim", Receiving: "receiving" };
const RECORD_TYPES = new Set<string>(["MX", "TXT", "CNAME"]);

function isRecordType(type: string): type is DnsRecord["type"] {
    return RECORD_TYPES.has(type);
}

// Resend's own tracking records are dropped: tracking runs through our host, see the domains service.
function dnsRecords(
    records: { record: string; type: string; name: string; value: string; priority?: number; status: string }[],
) {
    return records.flatMap((record): DnsRecord[] => {
        const purpose = PURPOSES[record.record];
        if (!purpose || !isRecordType(record.type)) return [];
        return [
            {
                purpose,
                type: record.type,
                name: record.name,
                value: record.value,
                ...(record.priority === undefined ? {} : { priority: record.priority }),
                status: record.status === "verified" ? "verified" : record.status === "failed" ? "failed" : "pending",
            },
        ];
    });
}
