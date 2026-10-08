import type { Address } from "@repo/contracts";

const NAME_AND_ADDRESS = /^\s*"?(.*?)"?\s*<([^<>]+)>\s*$/;

/** Parses `Lena Peeters <lena@peeters.be>` or a bare address. Inbound headers are messy, so this never throws. */
export function parseAddress(raw: string): Address {
    const match = NAME_AND_ADDRESS.exec(raw);
    if (!match) return { email: raw.trim().toLowerCase() };
    const name = match[1]?.replaceAll('\\"', '"').trim();
    return { ...(name ? { name } : {}), email: (match[2] ?? "").trim().toLowerCase() };
}

/** Formats an address for a header, quoting the name so commas and quotes in it can't split the address list. */
export function formatAddress({ name, email }: Address): string {
    return name ? `"${name.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}" <${email}>` : email;
}

export function domainOf(email: string): string {
    return email.slice(email.lastIndexOf("@") + 1).toLowerCase();
}
