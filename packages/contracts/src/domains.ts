import { z } from "zod";

import { domainStatuses } from "./vocabulary";

export const dnsRecordSchema = z
    .object({
        purpose: z.enum(["dkim", "spf", "receiving", "tracking", "dmarc"]),
        type: z.enum(["MX", "TXT", "CNAME"]),
        name: z.string(),
        value: z.string(),
        priority: z.number().int().optional(),
        status: z.enum(["pending", "verified", "failed", "optional"]),
    })
    .meta({ id: "DnsRecord" });

// Wire format: dates travel as ISO strings, the api serializes and the app decodes against the generated client.
export const domainSchema = z
    .object({
        id: z.uuid(),
        name: z.string(),
        status: z.enum(domainStatuses),
        records: z.array(dnsRecordSchema),
        receivingEnabled: z.boolean(),
        catchAllMailboxId: z.uuid().nullable(),
        trackingHost: z.string(),
        trackingHostVerified: z.boolean(),
        createdAt: z.iso.datetime(),
        deletedAt: z.iso.datetime().nullable(),
    })
    .meta({ id: "Domain" });

export const domainListSchema = z.array(domainSchema);

export const createDomainSchema = z
    .object({
        name: z
            .string()
            .trim()
            .toLowerCase()
            .regex(
                /^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/,
                "Enter a domain like baree.be.",
            ),
    })
    .meta({ id: "CreateDomain" });

export const updateDomainSchema = z
    .object({
        receivingEnabled: z.boolean().optional(),
        catchAllMailboxId: z.uuid().nullable().optional(),
    })
    .meta({ id: "UpdateDomain" });

export type DnsRecord = z.infer<typeof dnsRecordSchema>;
export type Domain = z.infer<typeof domainSchema>;
export type CreateDomainInput = z.infer<typeof createDomainSchema>;
export type UpdateDomainInput = z.infer<typeof updateDomainSchema>;
