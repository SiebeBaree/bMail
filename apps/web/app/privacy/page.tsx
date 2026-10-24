import type { Metadata } from "next";

import { ContactLink, LegalPage } from "@/components/legal";

export const metadata: Metadata = {
    title: "Privacy policy · bMail",
    description: "What bMail does with your email and your Google account data.",
    alternates: { canonical: "/privacy" },
};

export default function Privacy() {
    return (
        <LegalPage title="Privacy policy" updated="October 24, 2026">
            <p>
                bMail is an email app for Mac and iPhone made by Siebe Baree. It runs on your device and talks to Google
                and to servers you choose. I don&apos;t run a bMail server, so your mail never passes through anything I
                operate. This policy explains what the app reads, where that data goes and what you can do about it.
            </p>

            <h2>What stays on your device</h2>
            <p>
                bMail keeps a copy of your mail in a local database on your Mac or iPhone so it can open instantly and
                work offline. That copy holds messages, attachments you open, labels, drafts and your settings. Sign-in
                tokens and API keys live in the system keychain. Removing an account or deleting the app removes its
                local mail.
            </p>

            <h2>Gmail and your Google account</h2>
            <p>
                When you add a Gmail account, bMail asks Google for permission to read, send and organize your mail (the{" "}
                <code>gmail.modify</code> scope) and for your name, email address and profile picture. The app uses this
                to:
            </p>
            <ul>
                <li>download your messages, threads, labels and attachments and show them to you</li>
                <li>send mail you write and save your drafts</li>
                <li>archive, delete, star, label and mark messages as read when you ask it to</li>
                <li>show which account a message belongs to</li>
            </ul>
            <p>
                bMail talks to Google directly from your device. Your Gmail data is not sent to me, sold, used for
                advertising or used to train AI models. Nobody reads it except you and the services you turn on below.
            </p>
            <p>
                bMail&apos;s use and transfer of information received from Google APIs will adhere to the{" "}
                <a href="https://developers.google.com/terms/api-services-user-data-policy">
                    Google API Services User Data Policy
                </a>
                , including the Limited Use requirements.
            </p>
            <p>
                You can revoke bMail&apos;s access at any time from your{" "}
                <a href="https://myaccount.google.com/permissions">Google account permissions</a> page or by removing
                the account in bMail.
            </p>

            <h2>Your own server</h2>
            <p>
                Custom domains, open and click tracking and synced labels run through a small server you deploy yourself
                on accounts you own (for example Vercel, Neon, Resend and Cloudflare R2). If you connect one, bMail
                stores on it the mail for your own domains, your labels and which conversations carry them, and the
                messages you choose to track along with their opens and clicks. That server and its data belong to you.
                Each provider you use handles the data under its own privacy policy.
            </p>

            <h2>AI features</h2>
            <p>
                Tab completion and auto labelling are off until you add an API key from an AI provider you pick (such as
                Anthropic, OpenAI or Mistral). When they&apos;re on, bMail sends the provider only what the feature
                needs, straight from your device with your key:
            </p>
            <ul>
                <li>
                    for tab completion, the email you&apos;re writing, the conversation you&apos;re replying to and a
                    few emails you sent before so suggestions sound like you
                </li>
                <li>
                    for auto labelling, the sender, subject and opening text of new inbox mail along with your label
                    descriptions
                </li>
            </ul>
            <p>
                The provider handles that data under its own terms. Turn a feature off or remove the key and bMail stops
                sending anything.
            </p>

            <h2>Agents on your Mac</h2>
            <p>
                The Mac app can let AI agents running on your Mac read or manage your mail. This is off for every
                account until you choose a level for it, it only listens on your own computer and every request needs a
                token you copy from Settings.
            </p>

            <h2>Open and click tracking</h2>
            <p>
                Tracking is off by default. When you turn it on for a message, your server adds an invisible image and
                rewrites links so it can count when recipients open the message or click a link. It records the time,
                the IP address and the browser or mail client of each open and click. Those records stay on your server.
            </p>

            <h2>This website</h2>
            <p>
                getbmail.si has no accounts, no cookies and no analytics. The host keeps standard request logs for
                security and reliability.
            </p>

            <h2>Children</h2>
            <p>bMail is not meant for children under 13 and I don&apos;t knowingly collect their data.</p>

            <h2>Changes</h2>
            <p>If this policy changes, I&apos;ll update it here and change the date at the top.</p>

            <h2>Contact</h2>
            <p>
                Questions or requests about your data go to <ContactLink />.
            </p>
        </LegalPage>
    );
}
