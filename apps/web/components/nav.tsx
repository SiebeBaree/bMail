import { LogoMark } from "@/components/logo";

const links = [
    { href: "#features", title: "Features" },
    { href: "#keyboard", title: "Keyboard" },
    { href: "#self-host", title: "Self-host" },
    { href: "#compare", title: "Compare" },
];

/** The brand sits dead center: the intro's dots land exactly on [data-brand-logo] and [data-brand-text]. */
export function Nav() {
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
                <p className="justify-self-end text-[14px] text-muted" data-reveal style={{ "--d": 300 }}>
                    Coming soon
                </p>
            </nav>
        </header>
    );
}
