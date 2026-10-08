import type { CreateMailboxInput, Mailbox, UpdateMailboxInput } from "@repo/contracts";
import type { Database } from "@repo/db";

import { toMailbox } from "../../lib/dto";
import { ConflictError, NotFoundError } from "../../lib/errors";
import { domainsRepo } from "../domains/domains.repo";
import { mailboxesRepo } from "./mailboxes.repo";

export function mailboxesService(db: Database) {
    const repo = mailboxesRepo(db);
    const domains = domainsRepo(db);

    async function withDomain(userId: string, id: string) {
        const row = await repo.findWithDomain(userId, id);
        if (!row) throw new NotFoundError("That mailbox doesn't exist anymore.");
        return row;
    }

    return {
        async create(userId: string, input: CreateMailboxInput): Promise<Mailbox> {
            const domain = await domains.find(userId, input.domainId);
            if (!domain) throw new NotFoundError("That domain doesn't exist anymore.");
            if (await repo.exists(domain.id, input.localPart)) {
                throw new ConflictError(`${input.localPart}@${domain.name} already exists.`);
            }
            const row = await repo.create({ ...input, userId });
            return toMailbox(row, domain.name);
        },
        async update(userId: string, id: string, input: UpdateMailboxInput): Promise<Mailbox> {
            const { domain } = await withDomain(userId, id);
            const row = await repo.update(userId, id, input);
            if (!row) throw new NotFoundError("That mailbox doesn't exist anymore.");
            return toMailbox(row, domain.name);
        },
        async remove(userId: string, id: string): Promise<void> {
            await withDomain(userId, id);
            await repo.remove(userId, id);
        },
    };
}
