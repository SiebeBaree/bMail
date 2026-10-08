import type { IncomingHttpHeaders } from "node:http";

/** Node's header object as a Fetch `Headers`, for libraries that speak the Fetch api (Better Auth, Resend). */
export function toFetchHeaders(headers: IncomingHttpHeaders): Headers {
    const result = new Headers();
    for (const [key, value] of Object.entries(headers)) {
        for (const entry of Array.isArray(value) ? value : value === undefined ? [] : [value])
            result.append(key, entry);
    }
    return result;
}

/** Message-IDs are compared as stored, so every one is stored the way headers carry it: in angle brackets. */
export function normalizeMessageId(id: string): string {
    const trimmed = id.trim();
    return trimmed.startsWith("<") ? trimmed : `<${trimmed}>`;
}
