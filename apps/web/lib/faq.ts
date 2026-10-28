import type { Release } from "./release";
import { site } from "./site";

export type Question = { question: string; answer: string };

/**
 * The questions people ask about bMail, answered in full sentences so search engines and AI assistants can quote them.
 * The FAQ section, its FAQPage structured data and llms.txt all read this one list.
 */
export function faq(release: Release): Question[] {
    return [
        {
            question: "What is bMail?",
            answer: "bMail is a free, open source email app for macOS. It works with Gmail and with addresses on your own domain, saves every change on your Mac first so nothing waits on a server and has a keyboard shortcut for every action.",
        },
        {
            question: "Is bMail free?",
            answer: "Yes. The app is free and open source under the MIT license. Gmail needs nothing else. Your own domains and tracking run on a small api you host yourself, and the free plans of Vercel, Neon and Resend are enough to run it.",
        },
        {
            question: "Which Macs does bMail run on?",
            answer: `bMail runs on ${site.platform} and later. It's a native app written in Swift and SwiftUI${release.size ? `, and the download is ${release.size}` : ""}.`,
        },
        {
            question: "Does bMail work with Gmail?",
            answer: "Yes. Sign in with Google and bMail syncs your Gmail straight from your Mac to Google, with no bMail account. You can add more than one account and read them together or one at a time.",
        },
        {
            question: "Can I use bMail with my own domain?",
            answer: "Yes. Add your domain in Settings and bMail shows the DNS records to create. Every address on it can then send and receive through Resend, right next to your Gmail. A catch-all address can collect mail sent to addresses that don't exist.",
        },
        {
            question: "Does bMail work offline?",
            answer: "Yes. Your mail is cached on your Mac and every change is saved there first. You can archive, label, star and write while offline, and bMail sends everything once you're back online.",
        },
        {
            question: "Where is my email stored?",
            answer: "On your Mac, in a local database. Gmail stays in your Google account. Mail for your own domain is stored in your own Postgres database on Neon and attachments in your own Vercel Blob store or Cloudflare R2 bucket. There is no shared bMail server.",
        },
        {
            question: "Do I need to host a server?",
            answer: "Only for your own domains and open tracking. Gmail works without one. The server is a small api you deploy to Vercel with one button, and the first bMail to connect to it owns it.",
        },
        {
            question: "Can bMail tell me when an email is opened?",
            answer: "Yes, for the messages you choose. Turn on tracking with ⌘⇧T while writing. bMail counts opens and clicks from people and leaves out automatic opens from Apple's privacy proxy and link scanners. Your own opens never count, and tracking is off by default.",
        },
        {
            question: "What keyboard shortcuts does bMail have?",
            answer: "J and K move between conversations, E marks one as done, S stars, R replies, C writes a new message and Z undoes. ⌘K opens a command palette that lists every command with its shortcut, and ? shows all of them.",
        },
        {
            question: "Is bMail a good Superhuman alternative?",
            answer: "If you use a Mac and want keyboard-first email without a subscription, yes. bMail is free, open source and native to macOS, and it also handles your own domain without a Google Workspace account.",
        },
        {
            question: "Is there a Windows, iPhone or web version?",
            answer: "No. bMail is a Mac app.",
        },
    ];
}
