import { ArrowRight } from "lucide-react";

import { Fit } from "@/components/fit";
import { Reveal } from "@/components/reveal";
import { setupGuideUrl } from "@/lib/release";

import { Diagram } from "./diagram";
import { Heading, Section } from "./frame";

const commands = [
    "git clone https://github.com/SiebeBaree/bMail.git",
    "cd bMail && pnpm install",
    "pnpm db:migrate",
    "pnpm --filter api password you@example.com",
];

export function SelfHost() {
    return (
        <Section id="self-host" className="grid gap-14 px-6 py-24 sm:px-12 lg:grid-cols-2 lg:items-center lg:py-32">
            <Reveal>
                <Heading title="Host it yourself for free">
                    <p>
                        There's no bMail server. Gmail connects straight from the app, and your own domain runs on a
                        small api you deploy to Vercel. The free plans from Neon, Resend and Cloudflare R2 are enough.
                    </p>
                </Heading>
                <div className="mt-10 overflow-hidden rounded-xl border border-line bg-canvas">
                    <div className="flex h-9 items-center gap-2 border-b border-line px-3.5">
                        <span className="size-2.5 rounded-full bg-line-strong" />
                        <span className="size-2.5 rounded-full bg-line-strong" />
                        <span className="size-2.5 rounded-full bg-line-strong" />
                        <span className="ml-2 font-mono text-[12px] text-faint">~/bMail</span>
                    </div>
                    <pre className="overflow-x-auto p-4 font-mono text-[13px] leading-[1.9]">
                        {commands.map((command) => (
                            <div key={command}>
                                <span className="text-faint select-none">$ </span>
                                {command}
                            </div>
                        ))}
                        <div className="text-faint"># then deploy apps/api to Vercel and sign in</div>
                    </pre>
                </div>
                <a
                    href={setupGuideUrl}
                    className="group mt-6 inline-flex items-center gap-1.5 text-[15px] text-link hover:text-fg"
                >
                    Read the setup guide
                    <ArrowRight className="size-4 transition-transform group-hover:translate-x-0.5" />
                </a>
            </Reveal>
            <Reveal delay={0.1}>
                <Fit width={640} height={440}>
                    <Diagram />
                </Fit>
            </Reveal>
        </Section>
    );
}
