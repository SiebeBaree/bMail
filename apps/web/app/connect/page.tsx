import type { Metadata } from "next";

import { LogoMark } from "@/components/logo";

import { OpenOnLoad } from "./open-on-load";

export const metadata: Metadata = {
    title: "Connect your server",
    robots: { index: false, follow: false },
};

/**
 * Where Vercel's deploy button lands after a new server deploys. Vercel appends `deployment-url`, the project's
 * production domain, usually without a scheme. The page hands it to bMail, which asks before it connects.
 */
export default async function ConnectPage({ searchParams }: PageProps<"/connect">) {
    const { "deployment-url": deploymentUrl } = await searchParams;
    const server = serverUrl(typeof deploymentUrl === "string" ? deploymentUrl : undefined);
    const link = server && `bmail://connect?server=${encodeURIComponent(server.origin)}`;

    return (
        <main className="flex min-h-dvh items-center justify-center px-6">
            <div className="flex w-full max-w-[320px] flex-col items-start gap-3">
                <LogoMark size={36} className="mb-2" />
                <h1 className="text-[22px] font-semibold tracking-[-0.4px]">
                    {server ? "Your server is live" : "Connect your server"}
                </h1>
                {server && link ? (
                    <>
                        <p className="text-muted">{server.host}</p>
                        <a
                            href={link}
                            className="mt-2 inline-flex h-9 items-center rounded-md bg-fg px-4 text-[14px] font-medium text-canvas"
                        >
                            Open bMail
                        </a>
                        <OpenOnLoad href={link} />
                    </>
                ) : (
                    <p className="text-muted">In bMail, add an address on your own domain and enter your server.</p>
                )}
            </div>
        </main>
    );
}

/** The server's https origin, or null when what Vercel sent isn't a web address. */
function serverUrl(text: string | undefined): URL | null {
    if (!text) return null;
    try {
        const url = new URL(text.includes("://") ? text : `https://${text}`);
        return url.protocol === "https:" && url.hostname ? url : null;
    } catch {
        return null;
    }
}
