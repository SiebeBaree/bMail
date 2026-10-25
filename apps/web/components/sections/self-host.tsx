import { Fit } from "@/components/fit";
import { Reveal } from "@/components/reveal";

import { Diagram } from "./diagram";
import { Heading, Section } from "./frame";

const steps = [
    "Deploy the api to Vercel with one button",
    "Open bMail and connect to it",
    "Paste a Resend key and add your domain",
];

export function SelfHost() {
    return (
        <Section id="self-host" className="grid gap-14 px-6 py-24 sm:px-12 lg:grid-cols-2 lg:items-center lg:py-32">
            <Reveal>
                <Heading title="Host it yourself for free">
                    <p>
                        There's no bMail server and no bMail account. Gmail connects straight from the app. Your own
                        domain and tracking run on a small api you deploy to Vercel, where the free plans from Neon and
                        Resend are enough.
                    </p>
                </Heading>
                <div className="mt-10 overflow-hidden rounded-xl border border-line bg-canvas">
                    <div className="flex h-9 items-center gap-2 border-b border-line px-3.5">
                        <span className="size-2.5 rounded-full bg-line-strong" />
                        <span className="size-2.5 rounded-full bg-line-strong" />
                        <span className="size-2.5 rounded-full bg-line-strong" />
                        <span className="ml-2 font-mono text-[12px] text-faint">Your server</span>
                    </div>
                    <ol className="p-4 font-mono text-[13px] leading-[1.9]">
                        {steps.map((step, index) => (
                            <li key={step}>
                                <span className="text-faint select-none">{index + 1} </span>
                                {step}
                            </li>
                        ))}
                    </ol>
                </div>
            </Reveal>
            <Reveal delay={0.1}>
                <Fit width={640} height={440}>
                    <Diagram />
                </Fit>
            </Reveal>
        </Section>
    );
}
