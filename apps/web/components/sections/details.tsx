import { BellOff, Check, CircleAlert, Search, Send, Star, Tag, Trash2 } from "lucide-react";
import type { ReactNode } from "react";

import { Keys, KeyCap, MailButton, StatusDot } from "@/components/demo/primitives";
import { Reveal } from "@/components/reveal";

import { Section } from "./frame";

const cells: { title: string; text: string; visual: ReactNode }[] = [
    {
        title: "Z takes it back.",
        text: "Every change shows a toast with Undo. Sent mail waits ten seconds first, so Z unsends too.",
        visual: (
            <div className="flex flex-col gap-2">
                <Toast icon={<Check className="size-[13px]" />} title="Marked as done" />
                <Toast icon={<Send className="size-[13px]" />} title="Sending in 8s" />
            </div>
        ),
    },
    {
        title: "Unsubscribe without a browser.",
        text: "When a newsletter supports one-click unsubscribe, bMail sends the request itself.",
        visual: (
            <div className="flex flex-col items-start gap-3">
                <div className="flex items-center gap-1 rounded-lg border border-line bg-canvas py-1 pr-1 pl-3">
                    <span className="pr-3 font-mono text-[12px] text-muted">issues@paperplane.example</span>
                    <MailButton kind="ghost" className="bg-hover text-fg">
                        Unsubscribe
                    </MailButton>
                </div>
                <Toast
                    icon={<BellOff className="size-[13px] text-success" />}
                    title="Unsubscribed from Paperplane Weekly"
                    undo={false}
                />
            </div>
        ),
    },
    {
        title: "Search on your Mac.",
        text: "The index sits next to your mail, so results come in as you type, offline too.",
        visual: (
            <div className="w-full max-w-[330px] overflow-hidden rounded-lg border border-line-strong bg-canvas">
                <div className="flex h-[34px] items-center gap-2 border-b border-line px-2.5">
                    <Search className="size-3 text-muted" />
                    <span>contract</span>
                    <span className="h-3.5 w-px bg-fg" />
                </div>
                {[
                    ["Priya Raman", "Re: Contract for the Halden rebrand", "9:58 AM"],
                    ["Ada Okafor", "Contract renewal for 2027", "Aug 14"],
                ].map(([who, subject, time]) => (
                    <div
                        key={subject}
                        className="flex flex-col gap-0.5 border-b border-line/60 px-3 py-2 last:border-0"
                    >
                        <span className="flex justify-between">
                            <span className="font-medium text-fg-2">{who}</span>
                            <span className="font-mono text-[12px] text-muted">{time}</span>
                        </span>
                        <Match text={subject ?? ""} query="contract" />
                    </div>
                ))}
            </div>
        ),
    },
    {
        title: "Know when mail bounces.",
        text: "Sent mail shows Delivered or Bounced, with the receiving server's own words when it fails.",
        visual: (
            <div className="flex w-full max-w-[340px] flex-col gap-3">
                <span className="flex items-center gap-2 text-[12px] text-muted">
                    <StatusDot tone="success" />
                    Delivered
                    <span className="ml-auto font-mono">10:02 AM</span>
                </span>
                <span className="flex items-center gap-2 text-[12px] text-muted">
                    <StatusDot tone="danger" />
                    Bounced
                    <span className="ml-auto font-mono">10:03 AM</span>
                </span>
                <span className="flex gap-2 rounded-lg border border-line bg-canvas p-3 leading-[1.5]">
                    <CircleAlert className="mt-0.5 size-3.5 shrink-0 text-danger" />
                    <span>
                        Bounced.{" "}
                        <span className="text-muted">
                            550 5.1.1 The email account that you tried to reach does not exist.
                        </span>
                    </span>
                </span>
            </div>
        ),
    },
    {
        title: "Triage in bulk.",
        text: "X picks a conversation, ⇧J adds the next and ⌘A takes the list. Then one key handles all of them.",
        visual: (
            <div className="w-full max-w-[300px]">
                <p className="pb-2 text-[17px] font-semibold tracking-[-0.3px]">3 conversations selected</p>
                {(
                    [
                        [<Check key="i" className="size-3" />, "Mark as done", ["E"]],
                        [<Trash2 key="i" className="size-3" />, "Move to trash", ["⌘⌫"]],
                        [<Star key="i" className="size-3" />, "Star", ["S"]],
                        [<Tag key="i" className="size-3" />, "Label", ["L"]],
                    ] as const
                ).map(([icon, title, keys], index) => (
                    <div
                        key={title}
                        className={`flex h-8 items-center gap-2.5 rounded px-2 ${index === 0 ? "bg-selected text-fg" : "text-fg-2"}`}
                    >
                        <span className="w-[18px]">{icon}</span>
                        {title}
                        <span className="flex-1" />
                        <Keys keys={keys} />
                    </div>
                ))}
            </div>
        ),
    },
    {
        title: "One set of labels.",
        text: "Labels belong to bMail, so the same label works across Gmail and your domains. Each one gets a tab.",
        visual: (
            <div className="w-full max-w-[280px] rounded-lg border border-line-strong bg-raised p-1 shadow-[0_16px_40px_rgb(0_0_0/0.5)]">
                <div className="flex h-9 items-center border-b border-line px-2.5 text-muted">Label as</div>
                {[
                    ["Clients", true],
                    ["Receipts", false],
                    ["Travel", true],
                ].map(([name, on]) => (
                    <div
                        key={String(name)}
                        className={`mt-1 flex h-8 items-center gap-2.5 rounded px-2 ${name === "Receipts" ? "bg-selected" : ""}`}
                    >
                        <span
                            className={`flex size-3.5 items-center justify-center rounded-[4px] border ${on ? "border-accent bg-accent" : "border-line-strong"}`}
                        >
                            {on && <Check className="size-2.5 text-white" strokeWidth={3} />}
                        </span>
                        {name}
                    </div>
                ))}
            </div>
        ),
    },
];

function Match({ text, query }: { text: string; query: string }) {
    const start = text.toLowerCase().indexOf(query);
    return (
        <span className="truncate text-fg-2">
            {text.slice(0, start)}
            <mark className="rounded-sm bg-warning/25 text-fg">{text.slice(start, start + query.length)}</mark>
            {text.slice(start + query.length)}
        </span>
    );
}

function Toast({ icon, title, undo = true }: { icon: ReactNode; title: string; undo?: boolean }) {
    return (
        <div className="flex min-h-[46px] w-[330px] items-center gap-2.5 rounded-lg border border-line-strong bg-raised py-2 pr-2 pl-3.5 shadow-[0_8px_32px_rgb(0_0_0/0.35)]">
            <span className="text-fg-2">{icon}</span>
            <span className="flex-1 truncate">{title}</span>
            {undo && (
                <MailButton kind="secondary" className="h-[26px] px-2.5">
                    Undo
                    <KeyCap>Z</KeyCap>
                </MailButton>
            )}
        </div>
    );
}

export function Details() {
    return (
        <Section className="px-0">
            <div className="px-6 pt-24 pb-14 sm:px-12 lg:pt-32">
                <Reveal>
                    <h2 className="max-w-[700px] text-[clamp(34px,4.6vw,56px)] leading-[1.02] font-semibold tracking-[-0.045em]">
                        Everything else you'd expect
                    </h2>
                    <p className="mt-5 max-w-[470px] text-[17px] leading-[1.6] text-fg-2">
                        Undo send, one-click unsubscribe, labels, bulk actions and search that works offline.
                    </p>
                </Reveal>
            </div>
            <div className="grid gap-px border-t border-line bg-line md:grid-cols-2 lg:grid-cols-3">
                {cells.map((cell, index) => (
                    <Reveal key={cell.title} delay={(index % 3) * 0.08} className="bg-chrome">
                        <div className="flex h-full flex-col p-8">
                            <div
                                aria-hidden
                                data-nosnippet
                                className="flex h-[200px] items-center justify-center text-[13px] text-fg"
                            >
                                {cell.visual}
                            </div>
                            <h3 className="mt-8 text-[17px] font-medium tracking-[-0.01em]">{cell.title}</h3>
                            <p className="mt-2 text-[15px] leading-[1.55] text-muted">{cell.text}</p>
                        </div>
                    </Reveal>
                ))}
            </div>
        </Section>
    );
}
