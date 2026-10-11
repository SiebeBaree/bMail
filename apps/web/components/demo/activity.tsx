"use client";

import { useState } from "react";

import type { ActivityEvent, Message } from "./data";
import { MailButton, StatusDot } from "./primitives";

const titles = { delivered: "Delivered", opened: "Opened", clicked: "Clicked" } as const;

/**
 * What happened to a message you sent (App/Tracking/ActivityView.swift): delivery, then every open and click, people
 * and machines apart. Machines are hollow and never counted.
 */
export function Activity({ activity }: { activity: NonNullable<Message["activity"]> }) {
    const [open, setOpen] = useState(true);
    const { events, links } = activity;
    const opens = events.filter((event) => event.kind === "opened" && event.reader).length;
    const clicks = events.filter((event) => event.kind === "clicked" && event.reader).length;
    const last = events.findLast((event) => event.kind !== "delivered" && event.reader);
    const delivered = events.find((event) => event.kind === "delivered");

    return (
        <div className="rounded-lg border border-line p-4">
            <div className="flex items-center gap-7 text-muted">
                {delivered && (
                    <span className="flex items-center gap-[7px]">
                        <StatusDot tone="success" />
                        Delivered {delivered.time.split(" ")[0]}
                    </span>
                )}
                <Count value={opens} noun="open" />
                <Count value={clicks} noun="click" />
                {last && (
                    <span>
                        Last activity <span className="text-fg">{last.time}</span>
                    </span>
                )}
                <span className="flex-1" />
                <MailButton kind="ghost" onClick={() => setOpen(!open)}>
                    {open ? "Hide activity" : "Show activity"}
                </MailButton>
            </div>
            {open && (
                <div className="mt-3.5 flex flex-col gap-3.5">
                    <Strip events={events} />
                    <div>
                        {events.toReversed().map((event) => (
                            <TimelineRow key={`${event.kind}-${event.at}`} event={event} />
                        ))}
                    </div>
                    {links.length > 0 && (
                        <div>
                            <div className="pb-2 font-semibold">Links</div>
                            {links.map((link) => (
                                <div key={link.url} className="flex justify-between border-b border-line py-2">
                                    <span>{link.url}</span>
                                    <span className="font-mono text-[12px] text-muted">
                                        {link.scanners > 0 ? `${link.people} · ${link.scanners} scanner` : link.people}
                                    </span>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            )}
        </div>
    );
}

function Count({ value, noun }: { value: number; noun: string }) {
    return (
        <span>
            <span className="text-[15px] font-semibold text-fg">{value}</span> {noun}
            {value === 1 ? "" : "s"}
        </span>
    );
}

/** Opens and clicks on one time axis, one lane each. Filled dots are people, hollow ones are machines. */
function Strip({ events }: { events: ActivityEvent[] }) {
    const end = Math.max(60, ...events.map((event) => event.at));
    const first = events[0];
    const last = events.at(-1);
    return (
        <div className="relative h-[74px] font-mono text-[12px]">
            {(["opened", "clicked"] as const).map((kind, lane) => (
                <div key={kind} className="absolute inset-x-0 flex items-center" style={{ top: lane === 0 ? 8 : 34 }}>
                    <span className="w-[52px] text-muted">{kind === "opened" ? "Opens" : "Clicks"}</span>
                    <span className="relative h-4 flex-1">
                        <span className="absolute inset-x-0 top-1/2 h-px bg-line" />
                        {events
                            .filter((event) => event.kind === kind)
                            .map((event) => (
                                <span
                                    key={event.at}
                                    className={`absolute top-1/2 size-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full ${event.reader ? "bg-fg ring-2 ring-canvas" : "border-[1.25px] border-faint bg-canvas"}`}
                                    style={{
                                        left: `calc(6px + ${(event.at / end) * 100}% - ${(event.at / end) * 12}px)`,
                                    }}
                                />
                            ))}
                    </span>
                </div>
            ))}
            <div className="absolute inset-x-0 bottom-0 flex justify-between pl-[58px] text-faint">
                <span>{first?.time}</span>
                <span>{last?.time}</span>
            </div>
        </div>
    );
}

function TimelineRow({ event }: { event: ActivityEvent }) {
    const dot = !event.reader ? "border border-faint" : event.kind === "delivered" ? "bg-success" : "bg-fg";
    return (
        <div className={`flex items-baseline gap-3 py-1.5 ${event.reader ? "text-fg-2" : "text-faint"}`}>
            <span className={`size-2 shrink-0 translate-y-[-1px] rounded-full ${dot}`} />
            <span className="w-24 shrink-0 font-mono text-[12px]">{event.time}</span>
            <span className="w-20 shrink-0 font-medium">{titles[event.kind]}</span>
            <span className="truncate">{event.summary}</span>
        </div>
    );
}
