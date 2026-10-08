import { describe, expect, it } from "vitest";

import { formatAddress, parseAddress } from "./addresses";
import { instrumentHtml, snippetOf } from "./html";
import { createTrackingTokens } from "./tracking-token";

describe("parseAddress", () => {
    it.each([
        ["Lena Peeters <Lena@Peeters.be>", { name: "Lena Peeters", email: "lena@peeters.be" }],
        ['"Peeters, Lena" <lena@peeters.be>', { name: "Peeters, Lena", email: "lena@peeters.be" }],
        ["lena@peeters.be", { email: "lena@peeters.be" }],
        ["<lena@peeters.be>", { email: "lena@peeters.be" }],
    ])("parses %s", (raw, expected) => {
        expect(parseAddress(raw)).toEqual(expected);
    });

    it("round-trips names with quotes and commas", () => {
        const address = { name: 'Lena "LP" Peeters, CEO', email: "lena@peeters.be" };
        expect(parseAddress(formatAddress(address))).toEqual(address);
    });
});

describe("snippetOf", () => {
    it("stops at the quoted reply", () => {
        const body =
            "Works for me.\nSee you on the 14th.\n\nOn Tue, Oct 6, 2026 at 10:42 Siebe wrote:\n> Could we aim for mid October?";
        expect(snippetOf(body)).toBe("Works for me. See you on the 14th.");
    });
});

describe("instrumentHtml", () => {
    it("rewrites web links only and adds the pixel inside the body", () => {
        const seen: string[] = [];
        const html = instrumentHtml(
            '<html><body><a href="https://a.example">A</a><a href="mailto:x@y.z">Mail</a><a href="#top">Top</a></body></html>',
            {
                pixelUrl: "https://t.baree.be/o/token",
                rewriteLink: (url) => {
                    seen.push(url);
                    return "https://t.baree.be/c/1";
                },
            },
        );
        expect(seen).toEqual(["https://a.example"]);
        expect(html).toContain('href="mailto:x@y.z"');
        expect(html).toContain('href="#top"');
        expect(html).toMatch(/<img src="https:\/\/t\.baree\.be\/o\/token"[^>]*><\/body>/);
    });
});

describe("tracking tokens", () => {
    const tokens = createTrackingTokens("secret-secret-secret-secret-secret");
    const id = "8f14e45f-ceea-4b67-8a55-6a86e93ac3e1";

    it("verifies its own tokens", () => {
        expect(tokens.verify("open", tokens.create("open", id))).toBe(id);
    });

    it("rejects an open token used as a click, and edited tokens", () => {
        const token = tokens.create("open", id);
        expect(tokens.verify("click", token)).toBeNull();
        expect(tokens.verify("open", token.replace(id, crypto.randomUUID()))).toBeNull();
    });
});
