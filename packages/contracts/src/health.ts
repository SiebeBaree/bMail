import { z } from "zod";

export const healthSchema = z
    .object({
        status: z.literal("ok"),
        /** Whether a device owns this server yet. bMail asks before claiming one that's new. */
        claimed: z.boolean(),
    })
    .meta({ id: "Health" });
