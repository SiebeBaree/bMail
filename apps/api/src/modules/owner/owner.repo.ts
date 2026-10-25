import { ownerTokens, users, type Database, type Transaction } from "@repo/db";
import { asc, eq, sql } from "drizzle-orm";

// Any constant works, as long as nothing else locks it. It serializes claims, so two devices racing to claim a fresh
// server can't both create an owner.
const CLAIM_LOCK = 0x626d61696c;

export function ownerRepo(db: Database) {
    return {
        async isClaimed(): Promise<boolean> {
            const [row] = await db.select({ id: users.id }).from(users).limit(1);
            return row !== undefined;
        },
        async userIdForToken(tokenHash: string): Promise<string | null> {
            const [row] = await db
                .select({ userId: ownerTokens.userId })
                .from(ownerTokens)
                .where(eq(ownerTokens.tokenHash, tokenHash));
            return row?.userId ?? null;
        },
        /** Runs `claim` while holding the claim lock, with the oldest owner if there is one. */
        withClaimLock<T>(claim: (tx: Transaction, owner: string | null) => Promise<T>): Promise<T> {
            return db.transaction(async (tx) => {
                await tx.execute(sql`select pg_advisory_xact_lock(${CLAIM_LOCK})`);
                const [owner] = await tx.select({ id: users.id }).from(users).orderBy(asc(users.createdAt)).limit(1);
                return claim(tx, owner?.id ?? null);
            });
        },
        async createOwner(tx: Transaction, userId: string, tokenHash: string) {
            await tx.insert(users).values({ id: userId });
            await tx.insert(ownerTokens).values({ tokenHash, userId });
        },
        /** Every device signed in until now loses access, whichever owner row it belonged to. */
        async replaceTokens(tx: Transaction, userId: string, tokenHash: string) {
            await tx.delete(ownerTokens);
            await tx.insert(ownerTokens).values({ tokenHash, userId });
        },
    };
}
