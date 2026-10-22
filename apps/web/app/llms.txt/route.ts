import { faq } from "@/lib/faq";
import { site } from "@/lib/site";

/**
 * /llms.txt (llmstxt.org): the page's facts as Markdown for language models, built from the same data as the page so
 * the two can't drift apart.
 */
export function GET() {
    const text = [
        `# ${site.name}`,
        "",
        `> ${site.description}`,
        "",
        "## Facts",
        "",
        `- Platform: ${site.platform} and later, a native app written in Swift and SwiftUI`,
        "- Status: coming soon, not released yet",
        "- Price: free, open source under the MIT license",
        "- Accounts: Gmail, synced straight from the Mac, and addresses on your own domain, sending and receiving through Resend",
        "- Local first: every change is saved in a database on the Mac and synced in the background, so actions are instant and work offline",
        "- Keyboard: every action has a shortcut, and ⌘K opens a command palette that shows them",
        "- Tracking: optional open and click tracking per message that ignores Apple's privacy proxy, link scanners and your own opens",
        "- Hosting: there is no shared bMail server; every user deploys a small api to Vercel with Neon, Resend and Cloudflare R2",
        `- Made by ${site.author.name}`,
        "",
        "## FAQ",
        "",
        ...faq().flatMap(({ question, answer }) => [`### ${question}`, "", answer, ""]),
        "## Links",
        "",
        `- [Website](${site.url}): features, screenshots and comparison with other mail apps`,
        "",
    ].join("\n");
    return new Response(text, { headers: { "content-type": "text/markdown; charset=utf-8" } });
}
