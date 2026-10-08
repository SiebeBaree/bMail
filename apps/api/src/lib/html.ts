import { parse } from "node-html-parser";

const SNIPPET_LENGTH = 200;

/** Plain text for search and snippets. Prefers the sender's own text part, which is usually cleaner. */
export function textOf(html: string | null, text: string | null): string {
    if (text?.trim()) return text;
    if (!html) return "";
    const root = parse(html);
    root.querySelectorAll("style, script, head").forEach((node) => node.remove());
    return root.structuredText;
}

/** The first lines a reader sees, without quoted replies or the `On ... wrote:` line above them. */
export function snippetOf(body: string): string {
    const lines: string[] = [];
    for (const line of body.split("\n")) {
        if (line.trimStart().startsWith(">") || /^On .+ wrote:\s*$/.test(line.trim())) break;
        lines.push(line);
    }
    return lines.join(" ").replaceAll(/\s+/g, " ").trim().slice(0, SNIPPET_LENGTH);
}

type Instrumentation = {
    pixelUrl: string;
    /** Called once per tracked link in document order; returns the url that replaces it. */
    rewriteLink: (url: string) => string;
};

/**
 * Adds the open pixel and routes every http(s) link through the click redirect. mailto:, tel: and anchors are left
 * alone. Only the copy that goes to Resend is instrumented; the stored html stays exactly as written.
 */
export function instrumentHtml(html: string, { pixelUrl, rewriteLink }: Instrumentation): string {
    const root = parse(html);
    for (const anchor of root.querySelectorAll("a[href]")) {
        const href = anchor.getAttribute("href")?.trim();
        if (href && /^https?:\/\//i.test(href)) anchor.setAttribute("href", rewriteLink(href));
    }
    // Not display:none: some clients skip loading hidden images, which would make every open invisible.
    const pixel = `<img src="${pixelUrl}" width="1" height="1" alt="" style="width:1px;height:1px;border:0;opacity:0">`;
    const body = root.querySelector("body");
    if (body) body.insertAdjacentHTML("beforeend", pixel);
    else root.insertAdjacentHTML("beforeend", pixel);
    return root.toString();
}
