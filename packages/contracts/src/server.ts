import { z } from "zod";

/** The first device to claim a fresh server owns it. A claimed one only takes a claim with the host's CLAIM_CODE. */
export const claimInputSchema = z
    .object({
        code: z.string().min(1).max(200).optional(),
    })
    .meta({ id: "ClaimRequest" });

/** The owner token. The app keeps it in iCloud Keychain and sends it as a bearer token on every private call. */
export const claimSchema = z
    .object({
        token: z.string(),
    })
    .meta({ id: "Claim" });

export const serverStatusSchema = z
    .object({
        publicUrl: z.string(),
        /** Whether the server can send and receive mail for your domains. bMail asks for a key before the first one. */
        resend: z.boolean(),
    })
    .meta({ id: "ServerStatus" });

export const setResendKeySchema = z
    .object({
        apiKey: z.string().trim().startsWith("re_", "Resend keys start with re_.").max(200),
    })
    .meta({ id: "SetResendKey" });

export type ServerStatus = z.infer<typeof serverStatusSchema>;
