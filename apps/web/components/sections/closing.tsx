import { AppleLogo, GitHubLogo } from "@/components/brand-icons";
import { LogoMark } from "@/components/logo";
import { Reveal } from "@/components/reveal";
import { type Release, repoUrl, setupGuideUrl } from "@/lib/release";

import { Section } from "./frame";

export function Closing({ release }: { release: Release }) {
    return (
        <Section className="px-6 pt-28 pb-20 text-center sm:px-12">
            <div
                aria-hidden
                className="pointer-events-none absolute inset-x-0 top-0 h-[480px] bg-[radial-gradient(50%_60%_at_50%_45%,rgb(10_114_239/0.16),transparent_70%)]"
            />
            <Reveal>
                {/* The intro's dot-matrix word, at rest. */}
                <p
                    aria-hidden
                    className="bg-[radial-gradient(circle,#ededed_1.4px,transparent_1.7px)] bg-[length:7px_7px] bg-clip-text text-[clamp(120px,27vw,340px)] leading-[0.85] font-semibold tracking-[-0.06em] text-transparent select-none"
                >
                    bMail
                </p>
            </Reveal>
            <Reveal delay={0.1}>
                <h2 className="mt-12 text-[clamp(28px,3.4vw,40px)] font-semibold tracking-[-0.04em]">
                    Download bMail for free
                </h2>
                <p className="mx-auto mt-4 max-w-[460px] text-[17px] leading-[1.6] text-fg-2">
                    Works with Gmail and your own domain. Open source under the MIT license.
                </p>
                <div className="mt-9 flex flex-wrap justify-center gap-3">
                    <a
                        href={release.dmgUrl}
                        className="flex h-12 items-center gap-2.5 rounded-full bg-fg px-6 text-[15px] font-medium text-black transition-colors hover:bg-white"
                    >
                        <AppleLogo className="size-4 -translate-y-px" />
                        Download for Mac
                    </a>
                    <a
                        href={setupGuideUrl}
                        className="flex h-12 items-center rounded-full border border-line-strong px-6 text-[15px] font-medium text-fg transition-colors hover:bg-hover"
                    >
                        Host your api
                    </a>
                </div>
            </Reveal>
        </Section>
    );
}

export function Footer() {
    return (
        <footer className="mx-auto flex max-w-[1200px] flex-col gap-6 border-t border-line px-6 py-10 text-[14px] text-muted sm:flex-row sm:items-center sm:justify-between sm:px-12">
            <span className="flex items-center gap-2.5">
                <LogoMark size={20} />
                <span className="font-medium text-fg">bMail</span>
                <span className="text-faint">© 2026 Siebe Baree</span>
            </span>
            <nav className="flex flex-wrap gap-x-6 gap-y-2">
                <a href={repoUrl} className="flex items-center gap-1.5 hover:text-fg">
                    <GitHubLogo className="size-3.5" />
                    GitHub
                </a>
                <a href={`${repoUrl}/releases`} className="hover:text-fg">
                    Releases
                </a>
                <a href={setupGuideUrl} className="hover:text-fg">
                    Setup guide
                </a>
                <a href={`${repoUrl}/blob/main/LICENSE`} className="hover:text-fg">
                    MIT license
                </a>
            </nav>
        </footer>
    );
}
