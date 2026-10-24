import type { Metadata } from "next";
import Link from "next/link";

import { ContactLink, LegalPage } from "@/components/legal";

export const metadata: Metadata = {
    title: "Terms of service · bMail",
    description: "The terms for using the bMail app and website.",
    alternates: { canonical: "/terms" },
};

export default function Terms() {
    return (
        <LegalPage title="Terms of service" updated="October 24, 2026">
            <p>
                These terms cover the bMail apps for Mac and iPhone and the website getbmail.si, made by Siebe Baree. By
                using bMail you agree to them. If you don&apos;t, please don&apos;t use it.
            </p>

            <h2>The app</h2>
            <p>
                bMail is free and its source code is released under the MIT license. The license governs the code. These
                terms govern your use of the app as I distribute it.
            </p>

            <h2>Your accounts and services</h2>
            <p>
                bMail connects to accounts you already have, like Gmail, and to services you set up yourself, like your
                own server, Resend or an AI provider. You&apos;re responsible for those accounts, for keeping their
                credentials safe and for following their terms. Any costs they charge are yours.
            </p>

            <h2>Using bMail well</h2>
            <p>Don&apos;t use bMail to:</p>
            <ul>
                <li>send spam or mail people didn&apos;t ask for</li>
                <li>break the law or the rights of others</li>
                <li>get into accounts or systems you have no permission to use</li>
                <li>send malware or phishing</li>
            </ul>
            <p>
                Open and click tracking can be subject to privacy laws where you or your recipients live. Using it
                lawfully is up to you.
            </p>

            <h2>Your data</h2>
            <p>
                Your mail is yours. bMail stores it on your device and on services you control. The{" "}
                <Link href="/privacy">privacy policy</Link> explains exactly what goes where.
            </p>

            <h2>No warranty</h2>
            <p>
                bMail is provided as is, without warranties of any kind. I work hard to make it reliable but I
                can&apos;t promise it will be free of bugs or always available. Keep your own backups of mail that
                matters. Gmail keeps your mail on Google&apos;s side, and mail for your own domains lives in your own
                database.
            </p>

            <h2>Liability</h2>
            <p>
                To the extent the law allows, I&apos;m not liable for indirect or consequential damages or for lost
                data, profits or mail that comes from using bMail. Nothing in these terms limits liability that
                can&apos;t be limited by law.
            </p>

            <h2>Ending</h2>
            <p>
                You can stop using bMail at any time by removing your accounts and deleting the app. I may stop
                distributing it or change how it works.
            </p>

            <h2>Changes</h2>
            <p>
                I may update these terms. When I do I&apos;ll change the date at the top, and using bMail after that
                means you accept the new version.
            </p>

            <h2>Law</h2>
            <p>
                These terms fall under Belgian law, without taking away protections your local consumer law gives you.
            </p>

            <h2>Contact</h2>
            <p>
                Questions about these terms go to <ContactLink />.
            </p>
        </LegalPage>
    );
}
