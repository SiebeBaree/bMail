import type { MetadataRoute } from "next";

import { site } from "@/lib/site";

// Everyone may crawl everything, AI crawlers included: being quoted by assistants is the point.
export default function robots(): MetadataRoute.Robots {
    return {
        rules: { userAgent: "*", allow: "/" },
        sitemap: `${site.url}/sitemap.xml`,
        host: site.url,
    };
}
