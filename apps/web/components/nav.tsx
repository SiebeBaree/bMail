import { AppleLogo, GitHubLogo } from "@/components/brand-icons";
import { LogoMark } from "@/components/logo";
import { type Release, repoUrl } from "@/lib/release";

const links = [
    { href: "#features", title: "Features" },
    { href: "#keyboard", title: "Keyboard" },
    { href: "#self-host", title: "Self-host" },
    { href: "#compare", title: "Compare" },
];

/** The brand sits dead center: the intro's dots land exactly on [data-brand-logo] and [data-brand-text]. */
export function Nav({ release }: { release: Release }) {
    return (
        <header className="fixed inset-x-0 top-0 z-50 border-b border-line/70 bg-black/[0.92]">
            <nav className="mx-auto grid h-16 max-w-[1200px] grid-cols-[1fr_auto_1fr] items-center px-5">
                <ul className="hidden items-center gap-1 md:flex">
                    {links.map((link, index) => (
                        <li key={link.href} data-reveal style={{ "--d": 150 + index * 60 }}>
                            <a
                                href={link.href}
                                className="rounded-md px-3 py-1.5 text-[14px] text-muted transition-colors hover:text-fg"
                            >
                                {link.title}
                            </a>
                        </li>
                    ))}
                </ul>
                <a href="#top" data-brand className="col-start-2 flex items-center gap-2" aria-label="bMail home">
                    <span data-brand-logo className="block size-[22px]">
                        <LogoMark size={22} />
                    </span>
                    <span data-brand-text className="text-[17px] font-semibold tracking-[-0.03em]">
                        bMail
                    </span>
                </a>
                <div className="flex items-center justify-end gap-2" data-reveal style={{ "--d": 300 }}>
                    <a
                        href={repoUrl}
                        className="hidden size-9 items-center justify-center rounded-md text-muted transition-colors hover:text-fg sm:flex"
                        aria-label="bMail on GitHub"
                    >
                        <GitHubLogo className="size-[18px]" />
                    </a>
                    <a
                        href={release.dmgUrl}
                        className="flex h-8 items-center gap-2 rounded-md bg-fg px-3 text-[13px] font-medium text-black transition-colors hover:bg-white"
                    >
                        <AppleLogo className="size-3 -translate-y-px" />
                        Download
                    </a>
                </div>
            </nav>
        </header>
    );
}
