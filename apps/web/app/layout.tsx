import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import type { ReactNode } from "react";

import { site } from "@/lib/site";

import "./globals.css";

const sans = Geist({ subsets: ["latin"], variable: "--font-geist" });
const mono = Geist_Mono({ subsets: ["latin"], variable: "--font-geist-mono" });

// The OG image comes from app/opengraph-image.tsx; Next adds it to both cards.
export const metadata: Metadata = {
    metadataBase: new URL(site.url),
    title: site.title,
    description: site.description,
    applicationName: site.name,
    authors: [site.author],
    creator: site.author.name,
    category: "productivity",
    alternates: { canonical: "/", types: { "text/markdown": "/llms.txt" } },
    openGraph: {
        type: "website",
        url: "/",
        siteName: site.name,
        locale: "en_US",
        title: site.title,
        description: site.description,
    },
    twitter: { card: "summary_large_image", title: site.title, description: site.description },
    robots: {
        index: true,
        follow: true,
        googleBot: {
            index: true,
            follow: true,
            "max-image-preview": "large",
            "max-snippet": -1,
            "max-video-preview": -1,
        },
    },
};

export const viewport: Viewport = { themeColor: "#000000", colorScheme: "dark" };

// Runs before first paint. The intro plays unless motion is reduced or the link points somewhere down the page.
const introScript = `if(!location.hash&&!matchMedia("(prefers-reduced-motion: reduce)").matches)document.documentElement.dataset.intro="play"`;

export default function RootLayout({ children }: { children: ReactNode }) {
    return (
        // The intro script sets data-intro on <html> before React hydrates.
        <html lang="en" className={`${sans.variable} ${mono.variable}`} suppressHydrationWarning>
            <head>
                {/* oxlint-disable-next-line react/no-danger */}
                <script dangerouslySetInnerHTML={{ __html: introScript }} />
            </head>
            <body className="bg-chrome font-sans text-fg antialiased">{children}</body>
        </html>
    );
}
