import { Intro } from "@/components/intro/intro";
import { Nav } from "@/components/nav";
import { Closing, Footer } from "@/components/sections/closing";
import { Compare } from "@/components/sections/compare";
import { Details } from "@/components/sections/details";
import { Domains } from "@/components/sections/domains";
import { Faq } from "@/components/sections/faq";
import { Hero } from "@/components/sections/hero";
import { Instant } from "@/components/sections/instant";
import { KeyboardSection } from "@/components/sections/keyboard";
import { SelfHost } from "@/components/sections/self-host";
import { Tracking } from "@/components/sections/tracking";
import { faq } from "@/lib/faq";
import { structuredData } from "@/lib/structured-data";

export default function Home() {
    const questions = faq();
    return (
        <>
            <script
                type="application/ld+json"
                // Escaping < keeps any string in the data from closing the script tag.
                // oxlint-disable-next-line react/no-danger
                dangerouslySetInnerHTML={{
                    __html: JSON.stringify(structuredData(questions)).replace(/</g, "\\u003c"),
                }}
            />
            <Intro />
            <Nav />
            <main className="overflow-x-clip">
                <Hero />
                {/* The blueprint column: every section below shares these two hairlines. */}
                <div className="mx-auto mt-28 max-w-[1200px] border-x border-line">
                    <Instant />
                    <KeyboardSection />
                    <Tracking />
                    <Domains />
                    <Details />
                    <SelfHost />
                    <Compare />
                    <Faq questions={questions} />
                    <Closing />
                </div>
            </main>
            <Footer />
        </>
    );
}
