import { z } from "zod";

export const repoUrl = "https://github.com/SiebeBaree/bMail";
export const setupGuideUrl = `${repoUrl}#host-your-api`;
const latestUrl = `${repoUrl}/releases/latest`;

const GitHubRelease = z.object({
    tag_name: z.string(),
    assets: z.array(z.object({ name: z.string(), size: z.number(), browser_download_url: z.url() })),
});

/** `size` is the DMG's size the way Finder shows it, like "6.1 MB". */
export type Release = { version: string | null; dmgUrl: string; size: string | null };

const fallback: Release = { version: null, dmgUrl: latestUrl, size: null };

/**
 * The newest release's DMG, checked at most once an hour. Without GitHub (rate limits, no release yet) the button
 * still works: it points at the latest release page.
 */
export async function latestRelease(): Promise<Release> {
    try {
        const response = await fetch("https://api.github.com/repos/SiebeBaree/bMail/releases/latest", {
            headers: { accept: "application/vnd.github+json" },
            next: { revalidate: 3600 },
        });
        if (!response.ok) return fallback;
        const release = GitHubRelease.parse(await response.json());
        const dmg = release.assets.find((asset) => asset.name.endsWith(".dmg"));
        return {
            version: release.tag_name.replace(/^v/, ""),
            dmgUrl: dmg?.browser_download_url ?? latestUrl,
            size: dmg ? `${(dmg.size / 1_000_000).toFixed(1)} MB` : null,
        };
    } catch {
        return fallback;
    }
}
