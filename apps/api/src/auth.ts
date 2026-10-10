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
        // A password sign-up proves nothing about the email, so there is none: passwords come from `setPassword` below.
        // Sign-in refuses unverified accounts, which shuts out any that an earlier sign-up made.
        emailAndPassword: { enabled: true, minPasswordLength: 10, disableSignUp: true, requireEmailVerification: true },
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
                    // Accounts come from Google or Apple, which verified the email, or from `setPassword` below.
                    before: async (user) => {
                        const email = user.email.toLowerCase();
                        if (!allowedEmails.includes(email)) {
                            throw new APIError("FORBIDDEN", {
                                message: `${email} isn't in this server's ALLOWED_EMAILS.`,
                            });
                        }
                        if (!user.emailVerified) {
                            throw new APIError("FORBIDDEN", {
                                message: "Create your account with Google or Apple, or set a password on the server.",
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

/**
 * Gives an allowlisted email a new password, creating its account the first time. Whoever can run this holds the
 * database, which proves more than a sign-up form can, so the account counts as verified. Every existing session ends.
 * Returns the user's id.
 */
export async function setPassword(auth: Auth, email: string, password: string) {
    const { internalAdapter, password: hasher } = await auth.$context;
    const hash = await hasher.hash(password);
    const existing = await internalAdapter.findUserByEmail(email, { includeAccounts: true });
    if (!existing) {
        const user = await internalAdapter.createUser(
            { email, name: email.split("@")[0] ?? email, emailVerified: true },
            { method: "admin" },
        );
        await internalAdapter.linkAccount({
            userId: user.id,
            providerId: "credential",
            accountId: user.id,
            password: hash,
        });
        return user.id;
    }
    const { user, accounts: linked } = existing;
    await internalAdapter.updateUser(user.id, { emailVerified: true });
    await internalAdapter.deleteUserSessions(user.id);
    if (linked.some((account) => account.providerId === "credential")) {
        await internalAdapter.updatePassword(user.id, hash);
    } else {
        await internalAdapter.linkAccount({
            userId: user.id,
            providerId: "credential",
            accountId: user.id,
            password: hash,
        });
    }
    return user.id;
}
