import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";

import type { Database } from "@repo/db";

import { ConflictError } from "../../lib/errors";
import { ownerRepo } from "./owner.repo";

const sha256 = (value: string) => createHash("sha256").update(value).digest();
export const hashToken = (token: string) => sha256(token).toString("hex");

/**
 * Who owns this server. The first device to claim a fresh one gets the owner token, and the token is all a private
 * route checks. A claimed server only takes another claim with the host's CLAIM_CODE, which signs out every device.
 */
export function ownerService(db: Database, claimCode: string | undefined) {
    const repo = ownerRepo(db);

    return {
        isClaimed: repo.isClaimed,

        async claim(code: string | undefined): Promise<string> {
            const token = randomBytes(32).toString("base64url");
            const tokenHash = hashToken(token);
            await repo.withClaimLock(async (tx, owner) => {
                if (!owner) return repo.createOwner(tx, randomUUID(), tokenHash);
                if (!claimCode || code === undefined) {
                    throw new ConflictError(
                        "This server already has an owner. If it's yours, add CLAIM_CODE to the project on Vercel, redeploy and enter it here.",
                    );
                }
                // Comparing digests keeps the comparison constant time whatever the lengths.
                if (!timingSafeEqual(sha256(code), sha256(claimCode))) {
                    throw new ConflictError("That claim code doesn't match.");
                }
                return repo.replaceTokens(tx, owner, tokenHash);
            });
            return token;
        },

        /** The owner behind a bearer token, or null. */
        async userIdFor(bearer: string): Promise<string | null> {
            // Devices signed in before the claim existed send Better Auth's `token.signature`, percent-encoded, and the
            // migration kept the hash of `token`. Owner tokens are base64url, so they never contain a dot or a %.
            let token: string;
            try {
                token = decodeURIComponent(bearer).split(".")[0] ?? "";
            } catch {
                return null;
            }
            return token ? repo.userIdForToken(hashToken(token)) : null;
        },
    };
}

export type OwnerService = ReturnType<typeof ownerService>;
