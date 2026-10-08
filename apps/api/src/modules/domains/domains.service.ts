import type { DnsRecord, Domain, UpdateDomainInput } from "@repo/contracts";
import type { Database } from "@repo/db";

import { toDomain, trackingHostOf } from "../../lib/dto";
import { ConflictError, NotFoundError } from "../../lib/errors";
import type { ResendGateway } from "../../lib/resend";
import { mailboxesRepo } from "../mailboxes/mailboxes.repo";
import { domainsRepo } from "./domains.repo";

type Dependencies = { db: Database; resend: ResendGateway; publicUrl: string };

export function domainsService({ db, resend, publicUrl }: Dependencies) {
    const repo = domainsRepo(db);
    const apiHost = new URL(publicUrl).host;

    async function findOrThrow(userId: string, id: string) {
        const domain = await repo.find(userId, id);
        if (!domain) throw new NotFoundError("That domain doesn't exist anymore.");
        return domain;
    }

    // Resend's records plus the two we own: the tracking CNAME and a DMARC policy, which Resend doesn't ask for but
    // Gmail and Outlook increasingly do.
    function allRecords(name: string, resendRecords: DnsRecord[], trackingVerified: boolean): DnsRecord[] {
        return [
            ...resendRecords,
            {
                purpose: "tracking",
                type: "CNAME",
                name: "t",
                value: apiHost,
                status: trackingVerified ? "verified" : "pending",
            },
            {
                purpose: "dmarc",
                type: "TXT",
                name: "_dmarc",
                value: `v=DMARC1; p=none; rua=mailto:dmarc@${name}`,
                status: "optional",
            },
        ];
    }

    return {
        async list(userId: string): Promise<Domain[]> {
            return (await repo.list(userId)).map(toDomain);
        },
        async create(userId: string, name: string): Promise<Domain> {
            if (await repo.nameTaken(name)) throw new ConflictError(`${name} is already added.`);
            const remote = await resend.createDomain(name);
            const row = await repo.create({
                userId,
                name,
                resendDomainId: remote.id,
                status: remote.status,
                records: allRecords(name, remote.records, false),
            });
            return toDomain(row);
        },
        /** Asks Resend to check DNS again and probes the tracking host. The app calls this while records are pending. */
        async verify(userId: string, id: string): Promise<Domain> {
            const domain = await findOrThrow(userId, id);
            await resend.verifyDomain(domain.resendDomainId);
            const remote = await resend.getDomain(domain.resendDomainId);
            const trackingHostVerifiedAt =
                domain.trackingHostVerifiedAt ?? ((await trackingHostAnswers(domain.name)) ? new Date() : null);
            const row = await repo.update(userId, id, {
                status: remote.status,
                records: allRecords(domain.name, remote.records, trackingHostVerifiedAt !== null),
                trackingHostVerifiedAt,
            });
            if (!row) throw new NotFoundError("That domain doesn't exist anymore.");
            return toDomain(row);
        },
        async update(userId: string, id: string, input: UpdateDomainInput): Promise<Domain> {
            await findOrThrow(userId, id);
            if (input.catchAllMailboxId) {
                const mailbox = await mailboxesRepo(db).find(userId, input.catchAllMailboxId);
                if (mailbox?.domainId !== id) throw new NotFoundError("That mailbox isn't on this domain.");
            }
            const row = await repo.update(userId, id, input);
            if (!row) throw new NotFoundError("That domain doesn't exist anymore.");
            return toDomain(row);
        },
        async remove(userId: string, id: string): Promise<void> {
            const domain = await findOrThrow(userId, id);
            await resend.removeDomain(domain.resendDomainId);
            await repo.remove(userId, id);
        },
    };
}

/**
 * The tracking host counts as verified once https://t.<domain>/health answers through it, which proves DNS, TLS and
 * routing in one request. Until then tracked mail uses the api's own host.
 */
async function trackingHostAnswers(domainName: string): Promise<boolean> {
    try {
        const response = await fetch(`https://${trackingHostOf(domainName)}/health`, {
            signal: AbortSignal.timeout(3000),
        });
        return response.ok;
    } catch {
        return false;
    }
}
