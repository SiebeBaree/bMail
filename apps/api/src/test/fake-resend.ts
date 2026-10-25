import type { DnsRecord } from "@repo/contracts";

import { BadRequestError, UpstreamError } from "../lib/errors";
import type { OutgoingEmail, ReceivedAttachment, ReceivedEmail, ResendGateway } from "../lib/resend";

const records = (status: DnsRecord["status"]): DnsRecord[] => [
    { purpose: "dkim", type: "TXT", name: "resend._domainkey", value: "p=MIGfMA0", status },
    { purpose: "spf", type: "MX", name: "send", value: "feedback-smtp.eu-west-1.amazonses.com", priority: 10, status },
    {
        purpose: "receiving",
        type: "MX",
        name: "@",
        value: "inbound-smtp.eu-west-1.amazonaws.com",
        priority: 10,
        status,
    },
];

/** The one key the fake Resend refuses, the way Resend refuses a sending-only or revoked key. */
export const REJECTED_KEY = "re_rejected";

/** Resend as the services see it, with every call recorded. Webhook signatures are valid when they say "valid". */
export function createFakeResend() {
    const sent: { email: OutgoingEmail; idempotencyKey: string }[] = [];
    const webhooks: { id: string; apiKey: string; endpoint: string; signingSecret: string }[] = [];
    const inbox = new Map<string, { email: ReceivedEmail; attachments: ReceivedAttachment[] }>();
    const domainStatus = new Map<string, "pending" | "verified">();
    let nextSendError: string | null = null;

    const gateway: ResendGateway = {
        async createDomain(name) {
            domainStatus.set(`rd_${name}`, "pending");
            return { id: `rd_${name}`, status: "pending", records: records("pending") };
        },
        async getDomain(id) {
            const status = domainStatus.get(id) ?? "pending";
            return { id, status, records: records(status) };
        },
        async verifyDomain() {},
        async removeDomain(id) {
            domainStatus.delete(id);
        },
        async send(email, idempotencyKey) {
            if (nextSendError) {
                const message = nextSendError;
                nextSendError = null;
                throw new UpstreamError(message);
            }
            const replay = sent.find((entry) => entry.idempotencyKey === idempotencyKey);
            if (!replay) sent.push({ email, idempotencyKey });
            return { id: `re_${idempotencyKey}` };
        },
        async getReceivedEmail(id) {
            const entry = inbox.get(id);
            if (!entry) throw new UpstreamError(`no received email ${id}`);
            return entry.email;
        },
        async listReceivedAttachments(id) {
            return inbox.get(id)?.attachments ?? [];
        },
        async verifyWebhook(payload, headers) {
            if (headers.get("svix-signature") !== "valid") throw new Error("invalid signature");
            return JSON.parse(payload);
        },
        async createWebhook(apiKey, endpoint) {
            if (apiKey === REJECTED_KEY)
                throw new BadRequestError("Resend didn't accept that key. Use a full access key.");
            const webhook = {
                id: `wh_${webhooks.length + 1}`,
                apiKey,
                endpoint,
                signingSecret: `whsec_${webhooks.length + 1}`,
            };
            webhooks.push(webhook);
            return webhook;
        },
        async removeWebhook(_apiKey, id) {
            const index = webhooks.findIndex((webhook) => webhook.id === id);
            if (index >= 0) webhooks.splice(index, 1);
        },
    };

    return {
        gateway,
        sent,
        webhooks,
        verifyDomain: (name: string) => domainStatus.set(`rd_${name}`, "verified"),
        failNextSend: (message: string) => {
            nextSendError = message;
        },
        /** Puts an email where `getReceivedEmail` finds it, the way Resend has it before the webhook fires. */
        deliver: (email: Partial<ReceivedEmail> & { id: string }, attachments: ReceivedAttachment[] = []) => {
            inbox.set(email.id, {
                attachments,
                email: {
                    messageId: `<${email.id}@mail.example>`,
                    from: "Lena Peeters <lena@peeters.example>",
                    to: ["siebe@baree.test"],
                    cc: [],
                    bcc: [],
                    replyTo: [],
                    receivedFor: [],
                    subject: "Contract draft v3",
                    html: "<p>Added the clauses we discussed.</p>",
                    text: "Added the clauses we discussed.",
                    headers: {},
                    createdAt: new Date().toISOString(),
                    rawUrl: null,
                    ...email,
                },
            });
        },
    };
}

export type FakeResend = ReturnType<typeof createFakeResend>;
