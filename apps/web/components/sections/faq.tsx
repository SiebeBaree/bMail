import { Reveal } from "@/components/reveal";
import type { Question } from "@/lib/faq";

import { Heading, Section } from "./frame";

/** Every answer stays visible, not folded away, so people, crawlers and AI assistants all read the same text. */
export function Faq({ questions }: { questions: Question[] }) {
    return (
        <Section id="faq" className="grid gap-12 px-6 py-24 sm:px-12 lg:grid-cols-[4fr_7fr] lg:py-32">
            <Reveal>
                <Heading title="Frequently asked questions" />
            </Reveal>
            <Reveal delay={0.1}>
                <div className="border-t border-line">
                    {questions.map(({ question, answer }) => (
                        <div key={question} className="border-b border-line py-6">
                            <h3 className="text-[17px] font-medium tracking-[-0.01em] text-fg">{question}</h3>
                            <p className="mt-2 max-w-[620px] text-[15px] leading-[1.6] text-muted">{answer}</p>
                        </div>
                    ))}
                </div>
            </Reveal>
        </Section>
    );
}
