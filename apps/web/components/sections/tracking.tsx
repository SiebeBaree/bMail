import { conversations } from "@/components/demo/data";
import { Window } from "@/components/demo/primitives";
import { StaticConversation } from "@/components/demo/static-conversation";
import { Fit } from "@/components/fit";
import { Reveal } from "@/components/reveal";

import { Heading, Section } from "./frame";

const proposal = conversations.find((c) => c.id === "proposal");

const legend = [
    { dot: "bg-fg", title: "A person", text: "Counted, with device and city." },
    {
        dot: "border border-faint",
        title: "A machine",
        text: "Apple's privacy proxy and link scanners. Shown, never counted.",
    },
    { dot: "bg-success", title: "Delivered", text: "The moment the receiving server accepts it." },
];

export function Tracking() {
    return (
        <Section id="tracking" className="grid gap-14 px-6 py-24 sm:px-12 lg:grid-cols-[4fr_7fr] lg:py-32">
            <Reveal className="lg:pt-6">
                <Heading title="Know when your email is actually read">
                    <p>
                        Turn on tracking for a single message with ⌘⇧T. bMail leaves out automatic opens from Apple's
                        privacy proxy and link scanners, so the count only includes real people. Your own opens never
                        count.
                    </p>
                </Heading>
                <ul className="mt-10 flex flex-col gap-5 border-t border-line pt-8">
                    {legend.map((item) => (
                        <li key={item.title} className="flex gap-3.5">
                            <span className={`mt-[7px] size-2.5 shrink-0 rounded-full ${item.dot}`} />
                            <span className="text-[15px] leading-[1.55]">
                                <span className="text-fg">{item.title}.</span>{" "}
                                <span className="text-muted">{item.text}</span>
                            </span>
                        </li>
                    ))}
                </ul>
            </Reveal>
            <Reveal delay={0.1}>
                {proposal && (
                    <Fit width={780}>
                        <Window lights={false}>
                            <StaticConversation conversation={proposal} />
                        </Window>
                    </Fit>
                )}
            </Reveal>
        </Section>
    );
}
