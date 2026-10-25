"use client";

import { motion } from "motion/react";
import type { ReactNode } from "react";

import { LogoMark } from "@/components/logo";

type Node = { x: number; y: number; width: number; title: ReactNode; detail: string; strong?: boolean };

const nodes: Node[] = [
    {
        x: 0,
        y: 168,
        width: 168,
        title: (
            <span className="flex items-center gap-2">
                <LogoMark size={18} />
                bMail
            </span>
        ),
        detail: "On your Mac",
        strong: true,
    },
    { x: 236, y: 40, width: 172, title: "Gmail", detail: "Synced from the app" },
    { x: 236, y: 252, width: 172, title: "Your api", detail: "Vercel or any host", strong: true },
    { x: 476, y: 168, width: 164, title: "Resend", detail: "Sends and receives" },
    { x: 476, y: 252, width: 164, title: "Neon", detail: "Postgres" },
    { x: 476, y: 336, width: 164, title: "Blob or R2", detail: "Attachments" },
];

const HEIGHT = 56;
const mid = (node: Node | undefined) => (node ? node.y + HEIGHT / 2 : 0);
const [mac, gmail, api, resend, neon, storage] = nodes;

/** Every line is a real connection: the app talks to Gmail and your api; only the api talks to the services. */
const links: { d: string; dashed?: boolean; label?: { x: number; y: number; text: string } }[] = [
    { d: `M168 ${mid(mac)} C 202 ${mid(mac)}, 202 ${mid(gmail)}, 236 ${mid(gmail)}` },
    { d: `M168 ${mid(mac)} C 202 ${mid(mac)}, 202 ${mid(api)}, 236 ${mid(api)}` },
    { d: `M408 ${mid(api)} C 442 ${mid(api)}, 442 ${mid(resend)}, 476 ${mid(resend)}` },
    { d: `M408 ${mid(api)} L 476 ${mid(neon)}` },
    { d: `M408 ${mid(api)} C 442 ${mid(api)}, 442 ${mid(storage)}, 476 ${mid(storage)}` },
    {
        d: `M84 ${(mac?.y ?? 0) + HEIGHT} V ${mid(storage) + 40} H 558 V ${(storage?.y ?? 0) + HEIGHT}`,
        dashed: true,
        label: { x: 96, y: mid(storage) + 32, text: "attachments upload straight to storage" },
    },
];

export function Diagram() {
    return (
        <div className="relative h-[440px] w-[640px]">
            <svg className="absolute inset-0 overflow-visible" width={640} height={440} aria-hidden>
                <defs>
                    {/* User space, so the straight horizontal line (a zero-height box) still gets a gradient. */}
                    <linearGradient id="diagram-line" gradientUnits="userSpaceOnUse" x1="160" x2="480" y1="0" y2="0">
                        <stop offset="0" stopColor="#52a8ff" stopOpacity="0.9" />
                        <stop offset="1" stopColor="#52a8ff" stopOpacity="0.35" />
                    </linearGradient>
                </defs>
                {links.map((link, index) => (
                    <motion.path
                        key={link.d}
                        d={link.d}
                        fill="none"
                        stroke={link.dashed ? "#3a3a3a" : "url(#diagram-line)"}
                        strokeWidth={1.25}
                        strokeDasharray={link.dashed ? "4 5" : undefined}
                        // Drawing a path animates its dash array, so the dashed line only fades in.
                        initial={link.dashed ? { opacity: 0 } : { pathLength: 0, opacity: 0 }}
                        whileInView={link.dashed ? { opacity: 1 } : { pathLength: 1, opacity: 1 }}
                        viewport={{ once: true, margin: "0px 0px -15% 0px" }}
                        transition={{ duration: 0.9, delay: 0.3 + index * 0.12, ease: [0.2, 0.7, 0.2, 1] }}
                    />
                ))}
                {links.map(
                    (link) =>
                        link.label && (
                            <text
                                key={link.label.text}
                                x={link.label.x}
                                y={link.label.y}
                                className="fill-faint font-mono text-[11px]"
                            >
                                {link.label.text}
                            </text>
                        ),
                )}
            </svg>
            {nodes.map((node) => (
                <div
                    key={node.detail}
                    className={`absolute flex flex-col justify-center gap-0.5 rounded-lg border bg-canvas px-3.5 ${node.strong ? "border-line-strong" : "border-line"}`}
                    style={{ left: node.x, top: node.y, width: node.width, height: HEIGHT }}
                >
                    <span className="text-[14px] font-medium">{node.title}</span>
                    <span className="font-mono text-[11px] text-muted">{node.detail}</span>
                </div>
            ))}
        </div>
    );
}
