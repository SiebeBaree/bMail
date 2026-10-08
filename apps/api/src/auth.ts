import type { Database } from "@repo/db";
import { accounts, sessions, users, verifications } from "@repo/db";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { APIError } from "better-auth/api";
import { bearer } from "better-auth/plugins";

export type AuthOptions = {
    db: Database;
    baseURL: string;
    secret: string;
    /** Lowercased. Nobody outside this list can create an account, whichever way they sign in. */
    allowedEmails: string[];
    /** Client ids whose Google ID tokens are accepted, i.e. the macOS app's desktop OAuth client. */
    googleClientId?: string;
    /** The app's bundle id, the audience of the identity tokens Sign in with Apple hands the app. */
    appleBundleId?: string;
};

/**
 * Better Auth with three ways in: email and password, Google and Apple. The app is native, so every social sign-in is
 * an ID token the app obtained itself and posts to /api/auth/sign-in/social; no browser redirect ever ends here. The
 * bearer plugin returns the session token in the response and accepts it back as `Authorization: Bearer`.
 */
export function createAuth({ db, baseURL, secret, allowedEmails, googleClientId, appleBundleId }: AuthOptions) {
    return betterAuth({
        baseURL,
        secret,
        database: drizzleAdapter(db, {
            provider: "pg",
            schema: { user: users, session: sessions, account: accounts, verification: verifications },
        }),
        emailAndPassword: { enabled: true, minPasswordLength: 10 },
        socialProviders: {
            // Client secrets are only used by the browser redirect flow, which this api never runs.
            ...(googleClientId && { google: { clientId: googleClientId, clientSecret: "" } }),
            ...(appleBundleId && {
                apple: { clientId: appleBundleId, clientSecret: "", appBundleIdentifier: appleBundleId },
            }),
        },
        account: { accountLinking: { enabled: true, trustedProviders: ["google", "apple"] } },
        session: { expiresIn: 60 * 60 * 24 * 90, updateAge: 60 * 60 * 24 },
        databaseHooks: {
            user: {
                create: {
                    before: async (user) => {
                        if (!allowedEmails.includes(user.email.toLowerCase())) {
                            throw new APIError("FORBIDDEN", {
                                message: "This email isn't on the list for this server.",
                            });
                        }
                    },
                },
            },
        },
        plugins: [bearer()],
    });
}

export type Auth = ReturnType<typeof createAuth>;
