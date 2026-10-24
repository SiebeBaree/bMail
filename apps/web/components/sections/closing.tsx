import Link from "next/link";

import { LogoMark } from "@/components/logo";
import { Reveal } from "@/components/reveal";

import { Section } from "./frame";

export function Closing() {
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
                    bMail is coming soon
                </h2>
                <p className="mx-auto mt-4 max-w-[460px] text-[17px] leading-[1.6] text-fg-2">
                    Free for Gmail and your own domain. Open source under the MIT license.
                </p>
            </Reveal>
        </Section>
    );
}

export function Footer() {
    return (
        <footer className="mx-auto flex max-w-[1200px] flex-wrap items-center justify-between gap-4 border-t border-line px-6 py-10 text-[14px] text-muted sm:px-12">
            <span className="flex items-center gap-2.5">
                <LogoMark size={20} />
                <span className="font-medium text-fg">bMail</span>
                <span className="text-faint">© 2026 Siebe Baree</span>
            </span>
            <span className="flex gap-5">
                <Link href="/privacy" className="transition-colors hover:text-fg">
                    Privacy
                </Link>
                <Link href="/terms" className="transition-colors hover:text-fg">
                    Terms
                </Link>
            </span>
        </footer>
    );
}
