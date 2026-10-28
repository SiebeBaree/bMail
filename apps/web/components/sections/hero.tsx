import { AppleLogo, GitHubLogo } from "@/components/brand-icons";
import { type Release, repoUrl } from "@/lib/release";

import { HeroWindow } from "./hero-window";

export function Hero({ release }: { release: Release }) {
    return (
        <section id="top" className="relative overflow-hidden pt-36 sm:pt-44">
            {/* Static light: a cool glow behind the window and a dot grid that fades out toward the edges. */}
            <div
                aria-hidden
                data-reveal
                style={{ "--d": 200 }}
                className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(60%_45%_at_50%_62%,rgb(10_114_239/0.22),transparent_70%),radial-gradient(40%_30%_at_30%_70%,rgb(124_58_237/0.14),transparent_70%),radial-gradient(35%_25%_at_72%_58%,rgb(16_185_129/0.08),transparent_70%)]"
            />
            <div
                aria-hidden
                className="dot-grid pointer-events-none absolute inset-0 -z-10 [mask-image:radial-gradient(70%_55%_at_50%_30%,black,transparent)]"
            />

            <div className="mx-auto max-w-[1200px] px-5 text-center">
                <h1
                    data-reveal="lcp"
                    style={{ "--d": 80 }}
                    className="text-[clamp(48px,9vw,112px)] leading-[0.92] font-semibold tracking-[-0.06em] text-balance"
                >
                    Fast, native email
                    <br />
                    <span className="bg-gradient-to-b from-fg to-fg/45 bg-clip-text text-transparent">
                        for your Mac
                    </span>
                </h1>
                <p
                    data-reveal="lcp"
                    style={{ "--d": 220 }}
                    className="mx-auto mt-7 max-w-[560px] text-[clamp(16px,1.6vw,19px)] leading-[1.55] text-balance text-fg-2"
                >
                    bMail brings Gmail and your own domain into one app. Archive, reply and search without waiting, even
                    when you're offline.
                </p>
                <div data-reveal style={{ "--d": 340 }} className="mt-9 flex flex-wrap justify-center gap-3">
                    <a
                        href={release.dmgUrl}
                        className="flex h-12 items-center gap-2.5 rounded-full bg-fg px-6 text-[15px] font-medium text-black transition-colors hover:bg-white"
                    >
                        <AppleLogo className="size-4 -translate-y-px" />
                        Download for Mac
                    </a>
                    <a
                        href={repoUrl}
                        className="flex h-12 items-center gap-2.5 rounded-full border border-line-strong px-6 text-[15px] font-medium text-fg transition-colors hover:bg-hover"
                    >
                        <GitHubLogo className="size-4" />
                        Read the code
                    </a>
                </div>
                <p data-reveal style={{ "--d": 420 }} className="mt-5 font-mono text-[12px] text-faint">
                    {release.version ? `v${release.version} · ` : ""}macOS 27 · Free and open source
                </p>
            </div>

            <div data-reveal style={{ "--d": 520 }} className="mx-auto mt-16 max-w-[1320px] px-3 sm:mt-20 sm:px-5">
                <HeroWindow />
            </div>
        </section>
    );
}
