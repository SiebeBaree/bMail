import type { MessageEvent } from "@repo/contracts";
import type { FastifyRequest } from "fastify";

type Client = {
    source: NonNullable<MessageEvent["source"]>;
    device: string | null;
    city: string | null;
    country: string | null;
};

const SCANNERS =
    /bot|crawler|spider|scanner|curl|wget|python|go-http|headless|safelinks|barracuda|mimecast|proofpoint|symantec|trend ?micro/i;
// Security filters (Gmail's and corporate ones) load the pixel and click every link within seconds of delivery, from a
// datacenter with an ordinary browser user agent. A person doesn't read that fast.
const SCANNER_WINDOW_MS = 30_000;

/**
 * Who loaded the pixel or followed the link, as far as anyone can tell. Location comes from the host's geo headers
 * (Vercel's or Cloudflare's); the raw IP is never stored.
 */
export function classifyClient(request: FastifyRequest, sentAt: Date): Client {
    const userAgent = request.headers["user-agent"] ?? "";
    const header = (name: string) => {
        const value = request.headers[name];
        return typeof value === "string" && value ? decodeURIComponent(value) : null;
    };
    const location = {
        city: header("x-vercel-ip-city") ?? header("cf-ipcity"),
        country: header("x-vercel-ip-country") ?? header("cf-ipcountry"),
    };

    // Apple's Mail Privacy Protection fetches every image on delivery with exactly this user agent.
    if (userAgent.trim() === "Mozilla/5.0")
        return { source: "apple_proxy", device: "Apple Mail", city: null, country: null };
    if (SCANNERS.test(userAgent) || Date.now() - sentAt.getTime() < SCANNER_WINDOW_MS) {
        return { source: "scanner", device: null, ...location };
    }
    // Gmail loads images through its proxy when the recipient opens the mail, so this is a person reading.
    if (userAgent.includes("GoogleImageProxy"))
        return { source: "google_proxy", device: "Gmail", city: null, country: null };
    return { source: "person", device: deviceOf(userAgent), ...location };
}

const PLATFORMS: [string, RegExp][] = [
    ["iPhone", /iPhone/],
    ["iPad", /iPad/],
    ["Android", /Android/],
    ["Mac", /Macintosh|Mac OS X/],
    ["Windows", /Windows/],
    ["Linux", /Linux/],
];

const APPS: [string, RegExp][] = [
    ["Outlook", /Outlook|ms-office|Microsoft Office/i],
    ["Thunderbird", /Thunderbird/],
    ["Edge", /Edg\//],
    ["Chrome", /Chrome\//],
    ["Firefox", /Firefox\//],
    ["Safari", /Version\/.*Safari\//],
    ["Apple Mail", /AppleWebKit(?!.*Safari)/],
];

/** `Mac · Outlook`, `iPhone · Apple Mail`, `Windows · Chrome`. Good enough to tell readers apart, nothing more. */
function deviceOf(userAgent: string): string | null {
    const match = (table: [string, RegExp][]) => table.find(([, pattern]) => pattern.test(userAgent))?.[0];
    const parts = [match(PLATFORMS), match(APPS)].filter((part) => part !== undefined);
    return parts.length > 0 ? parts.join(" · ") : null;
}
