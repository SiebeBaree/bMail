import { createHmac, timingSafeEqual } from "node:crypto";

type TokenKind = "open" | "click";

// Tokens are `<uuid>.<signature>`: the id of the message (opens) or link (clicks), signed so a guessed or edited
// token is rejected before it reaches the database. The kind is part of the signature, so an open token can't be
// replayed as a click.
export function createTrackingTokens(secret: string) {
    const sign = (kind: TokenKind, id: string) =>
        createHmac("sha256", secret).update(`${kind}:${id}`).digest("base64url").slice(0, 22);

    return {
        create(kind: TokenKind, id: string): string {
            return `${id}.${sign(kind, id)}`;
        },
        /** The id the token was created for, or null when the signature doesn't match. */
        verify(kind: TokenKind, token: string): string | null {
            const [id, signature] = token.split(".");
            if (!id || !signature) return null;
            const expected = Buffer.from(sign(kind, id));
            const actual = Buffer.from(signature);
            return expected.length === actual.length && timingSafeEqual(expected, actual) ? id : null;
        },
    };
}

export type TrackingTokens = ReturnType<typeof createTrackingTokens>;
