"use client";

import { motion, useReducedMotion, useScroll, useTransform } from "motion/react";
import { useRef, useState } from "react";

import type { Command } from "@/components/demo/commands";
import { MailApp } from "@/components/demo/mail-app";
import { KeyCap } from "@/components/demo/primitives";
import { Fit } from "@/components/fit";

/** The working replica, tilted back and laid flat as you scroll, with the last key you pressed underneath. */
export function HeroWindow() {
    const ref = useRef<HTMLDivElement>(null);
    const reduced = useReducedMotion();
    const { scrollYProgress } = useScroll({ target: ref, offset: ["start end", "start 0.15"] });
    const rotateX = useTransform(scrollYProgress, [0, 1], reduced ? [0, 0] : [24, 0]);
    const scale = useTransform(scrollYProgress, [0, 1], reduced ? [1, 1] : [0.9, 1]);
    const [last, setLast] = useState<{ command: Command; at: number } | null>(null);

    return (
        <div ref={ref} className="[perspective:1800px]">
            <motion.div style={{ rotateX, scale, transformOrigin: "50% 0%" }} className="relative">
                {/* A thin line of light along the top edge, like Mintlify's hero frames. */}
                <div
                    aria-hidden
                    className="absolute -top-px left-1/2 z-10 h-px w-2/3 -translate-x-1/2 bg-gradient-to-r from-transparent via-link/70 to-transparent"
                />
                <Fit width={1240} height={760}>
                    <MailApp onCommand={(command) => setLast({ command, at: Date.now() })} />
                </Fit>
            </motion.div>
            <div className="mt-7 hidden h-8 items-center justify-center text-[14px] text-muted md:flex">
                {last ? (
                    <motion.span
                        key={last.at}
                        initial={{ opacity: 0, y: 4 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.18 }}
                        className="flex items-center gap-3"
                    >
                        <span className="flex gap-1">
                            {last.command.keys.map((key) => (
                                <KeyCap key={key} className="h-6 min-w-6 px-1.5 text-[12px]">
                                    {key}
                                </KeyCap>
                            ))}
                        </span>
                        <span className="text-fg">{last.command.title}</span>
                    </motion.span>
                ) : (
                    <span className="flex items-center gap-1.5">
                        Go ahead, press
                        <KeyCap className="h-6 min-w-6 text-[12px]">J</KeyCap>
                        <KeyCap className="h-6 min-w-6 text-[12px]">K</KeyCap>
                        <KeyCap className="h-6 min-w-6 text-[12px]">E</KeyCap>
                        or
                        <KeyCap className="h-6 min-w-6 px-1.5 text-[12px]">⌘K</KeyCap>
                    </span>
                )}
            </div>
        </div>
    );
}
