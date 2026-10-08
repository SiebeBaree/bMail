import { z } from "zod";

// Every non-2xx response has this shape. requestId is the reference a user can quote to support; issues carries
// field-level validation errors for 400s.
export const errorSchema = z
    .object({
        message: z.string(),
        requestId: z.string().optional(),
        issues: z.array(z.object({ path: z.string(), message: z.string() })).optional(),
    })
    .meta({ id: "Error" });

export const idParamSchema = z.object({
    id: z.uuid(),
});

/** An address on mail we send. Strict, because a typo here is a bounce. */
export const recipientSchema = z
    .object({
        name: z.string().trim().max(200).optional(),
        email: z.email().max(320),
    })
    .meta({ id: "Recipient" });

/** An address on mail we store. Lenient, because inbound mail is whatever the internet sent us. */
export const addressSchema = z
    .object({
        name: z.string().optional(),
        email: z.string(),
    })
    .meta({ id: "Address" });

export type ApiErrorBody = z.infer<typeof errorSchema>;
export type Address = z.infer<typeof addressSchema>;
