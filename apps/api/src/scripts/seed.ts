import { randomUUID } from "node:crypto";

import type { Address } from "@repo/contracts";
import { conversations, createDb, domains, events, links, mailboxes, messages } from "@repo/db";
import { env } from "@repo/env/api";
import { eq } from "drizzle-orm";

import { createAuth, setPassword } from "../auth";

// Local development only: fills a dev database with the inbox from the design mocks, so the app has something real
// to render without Resend. It only reads SEED_DATABASE_URL, never DATABASE_URL, so a .env pointing at production
// can't be seeded by accident: the seeded user has a known password.
if (process.env.NODE_ENV !== "development") throw new Error("The seed only runs with NODE_ENV=development.");
const seedDatabaseUrl = process.env.SEED_DATABASE_URL;
if (!seedDatabaseUrl) throw new Error("Set SEED_DATABASE_URL to a dev database to seed it.");

const OWNER = { email: env.ALLOWED_EMAILS[0] ?? "siebe@baree.be", password: "dev-password-123" };
const db = createDb(seedDatabaseUrl);
const auth = createAuth({
    db,
    baseURL: env.PUBLIC_URL,
    secret: env.BETTER_AUTH_SECRET,
    allowedEmails: env.ALLOWED_EMAILS,
});

const userId = await setPassword(auth, OWNER.email, OWNER.password);

const domainId = randomUUID();
const siebe = randomUUID();
const hello = randomUUID();
await db.insert(domains).values({
    id: domainId,
    userId,
    name: "baree.be",
    resendDomainId: `seed_${domainId}`,
    status: "verified",
    records: [
        {
            purpose: "dkim",
            type: "TXT",
            name: "resend._domainkey",
            value: "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC8",
            status: "verified",
        },
        {
            purpose: "spf",
            type: "MX",
            name: "send",
            value: "feedback-smtp.eu-west-1.amazonses.com",
            priority: 10,
            status: "verified",
        },
        { purpose: "spf", type: "TXT", name: "send", value: "v=spf1 include:amazonses.com ~all", status: "verified" },
        {
            purpose: "receiving",
            type: "MX",
            name: "@",
            value: "inbound-smtp.eu-west-1.amazonaws.com",
            priority: 10,
            status: "verified",
        },
        { purpose: "tracking", type: "CNAME", name: "t", value: "mail-api.baree.be", status: "pending" },
        {
            purpose: "dmarc",
            type: "TXT",
            name: "_dmarc",
            value: "v=DMARC1; p=none; rua=mailto:dmarc@baree.be",
            status: "optional",
        },
    ],
});
await db.insert(mailboxes).values([
    { id: siebe, userId, domainId, localPart: "siebe", displayName: "Siebe Baree" },
    { id: hello, userId, domainId, localPart: "hello", displayName: "baree" },
]);
await db.update(domains).set({ catchAllMailboxId: siebe }).where(eq(domains.id, domainId));

const me = (mailboxId: string): Address => ({
    name: "Siebe Baree",
    email: mailboxId === siebe ? "siebe@baree.be" : "hello@baree.be",
});
const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60_000);

type SeedMessage = { from: Address; body: string; minutesAgo: number; outbound?: boolean };

async function conversation(
    mailboxId: string,
    subject: string,
    thread: SeedMessage[],
    options: { read?: boolean; folder?: "inbox" | "done"; starred?: boolean } = {},
) {
    const conversationId = randomUUID();
    const last = thread.at(-1);
    const lastOutbound = thread.findLast((message) => message.outbound);
    await db.insert(conversations).values({
        id: conversationId,
        userId,
        mailboxId,
        subject,
        folder: options.folder ?? "inbox",
        isRead: options.read ?? false,
        isStarred: options.starred ?? false,
        lastMessageAt: minutesAgo(last?.minutesAgo ?? 0),
        lastOutboundAt: lastOutbound ? minutesAgo(lastOutbound.minutesAgo) : null,
    });
    const rows = thread.map((message, index) => ({
        id: randomUUID(),
        userId,
        conversationId,
        mailboxId,
        direction: message.outbound ? ("outbound" as const) : ("inbound" as const),
        deliveryStatus: message.outbound ? ("delivered" as const) : null,
        from: message.outbound ? me(mailboxId) : message.from,
        to: [message.outbound ? (thread.find((entry) => !entry.outbound)?.from ?? message.from) : me(mailboxId)],
        subject: index === 0 ? subject : `Re: ${subject}`,
        html: message.body
            .split("\n\n")
            .map((paragraph) => `<p>${paragraph.replaceAll("\n", "<br>")}</p>`)
            .join(""),
        text: message.body,
        snippet: message.body.replaceAll(/\s+/g, " ").slice(0, 200),
        sentAt: minutesAgo(message.minutesAgo),
    }));
    await db.insert(messages).values(rows.map((row) => ({ ...row, messageIdHeader: `<${row.id}@seed.baree.be>` })));
    const ids = rows.map((row) => row.id);
    return { conversationId, messageIds: ids };
}

const lena = { name: "Lena Peeters", email: "lena@peeters.be" };
const tom = { name: "Tom Verhaegen", email: "tom@northfund.vc" };
const pieter = { name: "Pieter Claes", email: "pieter@northfund.vc" };
const jan = { name: "Jan Wouters", email: "jan@wouters.be" };

await conversation(siebe, "Contract draft v3", [
    {
        from: lena,
        minutesAgo: 38,
        body: "Hi Siebe,\n\nAdded the clauses we discussed. Page 4 has the new termination terms, can you check before Friday?\n\nLena",
    },
]);
await conversation(siebe, "Seed round timeline", [
    {
        from: tom,
        outbound: true,
        minutesAgo: 60 * 48,
        body: "Hi Tom,\n\nFollowing up on our call. Could we aim for mid October for the first partner meeting?\n\nSiebe",
    },
    {
        from: pieter,
        minutesAgo: 60 * 24,
        body: "Adding myself here. I'll run diligence on our side and will need access to the data room.",
    },
    {
        from: tom,
        minutesAgo: 82,
        body: "Works for me. Let's lock the 14th for the partner meeting.\n\nBefore then it would help to have the updated model with October numbers, a short note on churn in the SMB segment and two customers we can call.\n\nI'll send an invite once Pieter confirms.\n\nTom",
    },
]);
await conversation(hello, "Your €4,210.00 payout is on its way", [
    {
        from: { name: "Stripe", email: "notifications@stripe.com" },
        minutesAgo: 130,
        body: "Your payout of €4,210.00 is expected in your account on October 10.",
    },
]);
await conversation(
    siebe,
    "Dinner Friday?",
    [
        {
            from: { name: "Arne Janssens", email: "arne@janssens.be" },
            minutesAgo: 222,
            body: "Found a new place in Ghent, they do a six course thing on Fridays. 8pm?",
        },
    ],
    { read: true },
);
await conversation(
    siebe,
    "Intro: Sarah and Siebe",
    [
        {
            from: { name: "Sarah Chen", email: "sarah@chen.vc" },
            minutesAgo: 60 * 26,
            body: "Siebe, meet Sarah. She runs growth at a fintech in Amsterdam and asked about how you set up onboarding.",
        },
    ],
    { read: true, starred: true },
);
await conversation(
    hello,
    "baree.be is verified",
    [
        {
            from: { name: "Resend", email: "no-reply@resend.com" },
            minutesAgo: 60 * 50,
            body: "You can now send and receive email on baree.be.",
        },
    ],
    { read: true },
);

const proposal = await conversation(
    siebe,
    "Proposal for Q4",
    [
        {
            from: jan,
            outbound: true,
            minutesAgo: 60 * 30,
            body: "Hi Jan,\n\nAs promised, the proposal for the Q4 retainer. Short version: two sprints in October, one in November and a fixed monthly fee after that.\n\nEverything is in baree.be/proposal. If it looks good, grab a slot: cal.com/siebe/30min\n\nSiebe",
        },
    ],
    { read: true, folder: "done" },
);
const [proposalId] = proposal.messageIds;
if (proposalId) {
    await db.update(messages).set({ trackingEnabled: true }).where(eq(messages.id, proposalId));
    const proposalLink = randomUUID();
    const calLink = randomUUID();
    await db.insert(links).values([
        { id: proposalLink, messageId: proposalId, position: 0, url: "https://baree.be/proposal" },
        { id: calLink, messageId: proposalId, position: 1, url: "https://cal.com/siebe/30min" },
    ]);
    const sentMinutesAgo = 60 * 30;
    const at = (afterSend: number) => minutesAgo(sentMinutesAgo - afterSend);
    await db.insert(events).values([
        { userId, messageId: proposalId, type: "sent", occurredAt: at(0) },
        { userId, messageId: proposalId, type: "delivered", detail: "Accepted by mx.wouters.be", occurredAt: at(0.05) },
        {
            userId,
            messageId: proposalId,
            type: "opened",
            source: "apple_proxy",
            device: "Apple Mail",
            occurredAt: at(0.1),
        },
        {
            userId,
            messageId: proposalId,
            type: "clicked",
            source: "scanner",
            linkId: proposalLink,
            occurredAt: at(0.15),
        },
        {
            userId,
            messageId: proposalId,
            type: "opened",
            source: "person",
            device: "Mac · Outlook",
            city: "Ghent",
            country: "BE",
            occurredAt: at(29),
        },
        {
            userId,
            messageId: proposalId,
            type: "clicked",
            source: "person",
            linkId: proposalLink,
            device: "Mac · Outlook",
            city: "Ghent",
            country: "BE",
            occurredAt: at(31),
        },
        {
            userId,
            messageId: proposalId,
            type: "opened",
            source: "person",
            device: "Windows · Outlook",
            city: "Brussels",
            country: "BE",
            occurredAt: at(60 * 12),
        },
        {
            userId,
            messageId: proposalId,
            type: "opened",
            source: "person",
            device: "Mac · Outlook",
            city: "Ghent",
            country: "BE",
            occurredAt: at(60 * 23),
        },
        {
            userId,
            messageId: proposalId,
            type: "clicked",
            source: "person",
            linkId: calLink,
            device: "Mac · Outlook",
            city: "Ghent",
            country: "BE",
            occurredAt: at(60 * 23 + 1),
        },
    ]);
}

process.stdout.write(`Seeded. Sign in as ${OWNER.email} / ${OWNER.password}\n`);
process.exit(0);
