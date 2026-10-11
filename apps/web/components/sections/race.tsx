"use client";

import { RotateCcw } from "lucide-react";
import { motion, useInView } from "motion/react";
import { useRef, useState } from "react";

/** Simulated milliseconds across the track, and how long the playhead takes to cross it. */
const SPAN = 600;
const ROUND_TRIP = 420;
const PLAY = 2.2;

const at = (ms: number) => `${(ms / SPAN) * 100}%`;
const delayFor = (ms: number) => (ms / SPAN) * PLAY;

/**
 * One click, two apps. The server-first lane waits a round trip before the list moves; bMail's list moves at zero and
 * the same round trip happens behind it. Plays once in slow motion when scrolled into view.
 */
export function Race() {
    const ref = useRef<HTMLDivElement>(null);
    const inView = useInView(ref, { once: true, margin: "0px 0px -20% 0px" });
    const [round, setRound] = useState(0);
    const playing = inView;

    return (
        <div ref={ref} className="rounded-2xl border border-line bg-canvas/80 p-6 sm:p-8">
            <div className="flex items-center justify-between font-mono text-[12px] text-muted">
                <span>You press E</span>
                <button
                    type="button"
                    onClick={() => setRound(round + 1)}
                    className="flex items-center gap-1.5 rounded-md px-2 py-1 transition-colors hover:bg-hover hover:text-fg"
                >
                    <RotateCcw className="size-3" />
                    Replay
                </button>
            </div>
            <div key={round} className="relative mt-8">
                <Lane
                    name="Server first"
                    playing={playing}
                    bar={{ to: ROUND_TRIP, label: "Waiting on the server", tone: "wait" }}
                    marker={{ at: ROUND_TRIP, label: `List moves · ${ROUND_TRIP} ms`, strong: false }}
                />
                <Lane
                    name="bMail"
                    playing={playing}
                    bar={{ to: ROUND_TRIP, label: "Syncing behind you", tone: "background" }}
                    marker={{ at: 0, label: "List moves · 0 ms", strong: true }}
                    end={{ at: ROUND_TRIP, label: "Synced" }}
                />
                <div className="relative mt-3 ml-[92px] h-5 border-t border-line font-mono text-[11px] text-faint">
                    {[0, 100, 200, 300, 400, 500, 600].map((ms) => (
                        <span key={ms} className="absolute top-1.5 -translate-x-1/2" style={{ left: at(ms) }}>
                            {ms}
                        </span>
                    ))}
                </div>
                <div className="pointer-events-none absolute inset-y-0 right-0 left-[92px]">
                    <motion.span
                        initial={{ left: "0%", opacity: 0 }}
                        animate={playing ? { left: "100%", opacity: [0, 1, 1, 0] } : undefined}
                        transition={{
                            duration: PLAY,
                            ease: "linear",
                            opacity: { times: [0, 0.03, 0.9, 1], duration: PLAY },
                        }}
                        className="absolute -top-3 bottom-6 w-px bg-gradient-to-b from-transparent via-link to-transparent"
                    />
                </div>
            </div>
            <p className="mt-6 text-[13px] text-muted">Slowed down to show what happens. The round trip is typical.</p>
        </div>
    );
}

function Lane({
    name,
    playing,
    bar,
    marker,
    end,
}: {
    name: string;
    playing: boolean;
    bar: { to: number; label: string; tone: "wait" | "background" };
    marker: { at: number; label: string; strong: boolean };
    end?: { at: number; label: string };
}) {
    return (
        <div className="flex h-[76px] items-center">
            <span className={`w-[92px] shrink-0 font-mono text-[12px] ${marker.strong ? "text-fg" : "text-muted"}`}>
                {name}
            </span>
            <div className="relative h-full flex-1">
                <span className="absolute inset-x-0 top-1/2 h-px bg-line" />
                <motion.span
                    initial={{ scaleX: 0 }}
                    animate={playing ? { scaleX: 1 } : undefined}
                    transition={{ duration: delayFor(bar.to), ease: "linear" }}
                    style={{ width: at(bar.to), originX: 0 }}
                    className={`absolute top-1/2 h-6 -translate-y-1/2 rounded-[5px] ${
                        bar.tone === "wait"
                            ? "border border-line-strong bg-[repeating-linear-gradient(135deg,rgb(255_255_255/0.07)_0_6px,transparent_6px_12px)]"
                            : "border border-dashed border-line bg-transparent"
                    }`}
                />
                <motion.span
                    initial={{ opacity: 0 }}
                    animate={playing ? { opacity: 1 } : undefined}
                    transition={{ delay: 0.2, duration: 0.4 }}
                    className={`absolute top-1/2 ml-6 -translate-y-1/2 text-[12px] whitespace-nowrap ${bar.tone === "wait" ? "text-fg-2" : "text-faint"}`}
                >
                    {bar.label}
                </motion.span>
                <Marker at={marker.at} label={marker.label} strong={marker.strong} playing={playing} />
                {end && <Marker at={end.at} label={end.label} strong={false} playing={playing} below />}
            </div>
        </div>
    );
}

function Marker({
    at: ms,
    label,
    strong,
    playing,
    below = false,
}: {
    at: number;
    label: string;
    strong: boolean;
    playing: boolean;
    below?: boolean;
}) {
    return (
        <motion.span
            initial={{ opacity: 0, scale: 0.6 }}
            animate={playing ? { opacity: 1, scale: 1 } : undefined}
            transition={{ delay: delayFor(ms), type: "spring", duration: 0.35, bounce: 0.3 }}
            className="absolute top-1/2 flex -translate-x-1/2 -translate-y-1/2 flex-col items-center"
            style={{ left: at(ms) }}
        >
            <span
                className={`size-3 rounded-full ${strong ? "bg-fg shadow-[0_0_0_4px_rgb(82_168_255/0.25),0_0_24px_rgb(82_168_255/0.6)]" : below ? "border border-success bg-canvas" : "bg-fg-2"}`}
            />
            <span
                className={`absolute ${below ? "top-5" : "bottom-5"} ${ms === 0 ? "left-0" : ""} font-mono text-[12px] whitespace-nowrap ${strong ? "text-fg" : below ? "text-success" : "text-fg-2"}`}
            >
                {label}
            </span>
        </motion.span>
    );
}
