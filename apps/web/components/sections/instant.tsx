import { Reveal } from "@/components/reveal";

import { Heading, Section } from "./frame";
import { Race } from "./race";

export function Instant() {
    return (
        <Section
            id="features"
            className="grid gap-14 px-6 py-24 sm:px-12 lg:grid-cols-[5fr_7fr] lg:items-center lg:py-32"
        >
            <Reveal>
                <Heading title="Every action is instant, even offline">
                    <p>
                        bMail saves your changes on your Mac first and syncs them with Gmail or your server in the
                        background. If you lose your connection, they go out as soon as you're back.
                    </p>
                </Heading>
            </Reveal>
            <Reveal delay={0.15}>
                <Race />
            </Reveal>
        </Section>
    );
}
