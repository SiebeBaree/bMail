import { AccountMenu } from "@/components/demo/mail-app";
import { Window } from "@/components/demo/primitives";
import { DomainSettings } from "@/components/demo/settings";
import { Fit } from "@/components/fit";
import { Reveal } from "@/components/reveal";

import { Heading, Section } from "./frame";

export function Domains() {
    return (
        <Section
            id="domains"
            className="grid gap-14 px-6 py-24 sm:px-12 lg:grid-cols-[7fr_5fr] lg:items-center lg:py-32"
        >
            <Reveal className="order-2 lg:order-1">
                <Fit width={760}>
                    <Window>
                        <DomainSettings />
                    </Window>
                </Fit>
            </Reveal>
            <Reveal delay={0.1} className="order-1 lg:order-2">
                <Heading title="Use Gmail and your own domain side by side">
                    <p>
                        Add your domain and bMail shows the DNS records to set up. Then you can send and receive from
                        any address on it, right next to your Gmail. Switch accounts with ⌘1 to ⌘9.
                    </p>
                </Heading>
                <div aria-hidden data-nosnippet className="mt-10 hidden sm:block">
                    <AccountMenu current={null} />
                </div>
            </Reveal>
        </Section>
    );
}
