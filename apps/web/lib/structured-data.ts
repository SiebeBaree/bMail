import type { Graph } from "schema-dts";

import type { Question } from "./faq";
import { type Release, repoUrl } from "./release";
import { site } from "./site";

/**
 * schema.org data for the page: the site, the app, its source code, its author and the FAQ. Search engines use it for
 * rich results and AI assistants for facts, so everything here must also be visible on the page.
 */
export function structuredData(release: Release, questions: Question[]): Graph {
    const app = `${site.url}/#app`;
    const author = `${site.url}/#author`;
    return {
        "@context": "https://schema.org",
        "@graph": [
            {
                "@type": "WebSite",
                "@id": `${site.url}/#website`,
                url: site.url,
                name: site.name,
                description: site.description,
                inLanguage: "en",
                publisher: { "@id": author },
            },
            {
                "@type": "Person",
                "@id": author,
                name: site.author.name,
                url: site.author.url,
            },
            {
                "@type": "SoftwareApplication",
                "@id": app,
                name: site.name,
                description: site.description,
                url: site.url,
                image: `${site.url}/opengraph-image`,
                applicationCategory: "CommunicationApplication",
                applicationSubCategory: "Email client",
                operatingSystem: `${site.platform} or later`,
                ...(release.version && { softwareVersion: release.version }),
                ...(release.size && { fileSize: release.size }),
                downloadUrl: release.dmgUrl,
                installUrl: release.dmgUrl,
                isAccessibleForFree: true,
                license: "https://opensource.org/licenses/MIT",
                offers: { "@type": "Offer", price: "0", priceCurrency: "EUR" },
                author: { "@id": author },
                sameAs: repoUrl,
                featureList: [
                    "Gmail and your own domain in one app",
                    "Every change saved locally first, so actions are instant and work offline",
                    "A keyboard shortcut for every action and a ⌘K command palette",
                    "Open and click tracking that ignores Apple's privacy proxy and link scanners",
                    "Undo send for 10 seconds",
                    "One-click unsubscribe",
                    "Labels shared across all accounts",
                    "Self-hosted api with no shared server",
                ],
            },
            {
                "@type": "SoftwareSourceCode",
                "@id": `${site.url}/#source`,
                name: `${site.name} source code`,
                codeRepository: repoUrl,
                programmingLanguage: ["Swift", "TypeScript"],
                license: "https://opensource.org/licenses/MIT",
                targetProduct: { "@id": app },
                author: { "@id": author },
            },
            {
                "@type": "FAQPage",
                "@id": `${site.url}/#faq`,
                mainEntity: questions.map(({ question, answer }) => ({
                    "@type": "Question",
                    name: question,
                    acceptedAnswer: { "@type": "Answer", text: answer },
                })),
            },
        ],
    };
}
