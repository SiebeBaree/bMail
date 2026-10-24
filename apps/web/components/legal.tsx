import Link from "next/link";
import type { ReactNode } from "react";

import { LogoMark } from "@/components/logo";
import { Footer } from "@/components/sections/closing";
import { site } from "@/lib/site";

/** The privacy policy and the terms: one readable column under a plain header that links home. */
export function LegalPage({ title, updated, children }: { title: string; updated: string; children: ReactNode }) {
    return (
        <>
            <header className="border-b border-line">
                <nav className="mx-auto flex h-16 max-w-[1200px] items-center px-5">
                    <Link href="/" className="flex items-center gap-2" aria-label="bMail home">
                        <LogoMark size={22} />
                        <span className="text-[17px] font-semibold tracking-[-0.03em]">bMail</span>
                    </Link>
                </nav>
            </header>
            <main className="mx-auto max-w-[720px] px-6 py-20 sm:py-28">
                <h1 className="text-[clamp(34px,4.6vw,48px)] leading-[1.05] font-semibold tracking-[-0.045em]">
                    {title}
                </h1>
                <p className="mt-4 text-[15px] text-muted">Last updated {updated}</p>
                <div className="mt-12 text-[16px] leading-[1.7] text-fg-2 [&_a]:text-link [&_a]:underline-offset-4 hover:[&_a]:underline [&_h2]:mt-12 [&_h2]:mb-3 [&_h2]:text-[20px] [&_h2]:font-semibold [&_h2]:tracking-[-0.02em] [&_h2]:text-fg [&_li]:mt-2 [&_p]:mt-4 [&_strong]:font-medium [&_strong]:text-fg [&_ul]:mt-4 [&_ul]:list-disc [&_ul]:pl-5">
                    {children}
                </div>
            </main>
            <Footer />
        </>
    );
}

export function ContactLink() {
    return <a href={`mailto:${site.contact}`}>{site.contact}</a>;
}
