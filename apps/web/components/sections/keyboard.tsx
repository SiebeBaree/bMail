"use client";

import { useInView } from "motion/react";
import { useEffect, useRef, useState } from "react";

import { type CommandId, commandById, tabs } from "@/components/demo/commands";
import { Fit } from "@/components/fit";
import { Reveal } from "@/components/reveal";

import { Heading, Section } from "./frame";

type Key = {
    /** KeyboardEvent.code, so Shift and layouts don't matter. */
    code: string;
    label: string;
    width?: number;
    command?: CommandId;
    /** The word printed under the letter. */
    word?: string;
    /** Function-row keys are half height. */
    short?: boolean;
};

const letters = (row: string, commands: Partial<Record<string, CommandId>>): Key[] =>
    [...row].map((letter) => {
        const command = commands[letter];
        return { code: `Key${letter}`, label: letter, command, word: command && commandById(command).short };
    });

/** A Mac keyboard with bMail's keymap printed on it. */
const rows: Key[][] = [
    [
        { code: "Escape", label: "esc", width: 1.5, short: true, command: "back", word: "Back" },
        ...Array.from({ length: 12 }, (_, index) => ({ code: `F${index + 1}`, label: `F${index + 1}`, short: true })),
        { code: "Power", label: "", width: 1.5, short: true },
    ],
    [
        { code: "Backquote", label: "`" },
        { code: "Digit1", label: "1", command: "spam", word: "! Spam" },
        ...[..."234567890"].map((digit) => ({ code: `Digit${digit}`, label: digit })),
        { code: "Minus", label: "-" },
        { code: "Equal", label: "=" },
        { code: "Backspace", label: "delete", width: 2, command: "trash", word: "⌘ Trash" },
    ],
    [
        { code: "Tab", label: "tab", width: 1.5 },
        ...letters("QWERTYUIOP", { E: "done", R: "reply", U: "read" }),
        { code: "BracketLeft", label: "[" },
        { code: "BracketRight", label: "]" },
        { code: "Backslash", label: "\\", width: 1.5 },
    ],
    [
        { code: "CapsLock", label: "caps lock", width: 1.75 },
        ...letters("ASDF", { A: "replyAll", S: "star", F: "forward" }),
        // G is a prefix: G then a tab's letter goes there.
        { code: "KeyG", label: "G", word: "Go to" },
        ...letters("HJKL", { J: "next", K: "previous", L: "label" }),
        { code: "Semicolon", label: ";" },
        { code: "Quote", label: "'" },
        { code: "Enter", label: "return", width: 2.25 },
    ],
    [
        { code: "ShiftLeft", label: "shift", width: 2.25 },
        ...letters("ZXCVBNM", { Z: "undo", X: "check", C: "compose" }),
        { code: "Comma", label: "," },
        { code: "Period", label: "." },
        { code: "Slash", label: "/", command: "search", word: "? Help" },
        { code: "ShiftRight", label: "shift", width: 2.75 },
    ],
    [
        { code: "Fn", label: "fn" },
        { code: "ControlLeft", label: "control" },
        { code: "AltLeft", label: "option" },
        { code: "MetaLeft", label: "command", width: 1.25, command: "palette", word: "K Palette" },
        { code: "Space", label: "", width: 4.5 },
        { code: "MetaRight", label: "command", width: 1.25 },
        { code: "AltRight", label: "option" },
        { code: "ArrowLeft", label: "←" },
        { code: "ArrowUp", label: "↑", command: "previous" },
        { code: "ArrowDown", label: "↓", command: "next" },
        { code: "ArrowRight", label: "→" },
    ],
];

const UNIT = 58;
const GAP = 6;

type Readout = { keys: readonly string[]; title: string } | { go: true } | null;

/**
 * Press a key and it lights up with what it does in bMail. G waits for a second key the way the app does. Only listens
 * while the keyboard is on screen.
 */
function Keyboard() {
    const ref = useRef<HTMLDivElement>(null);
    const onScreen = useInView(ref, { amount: 0.4 });
    const [pressed, setPressed] = useState<ReadonlySet<string>>(new Set());
    const [readout, setReadout] = useState<Readout>(null);
    const goRef = useRef(0);

    useEffect(() => {
        if (!onScreen) return;
        const show = (id: CommandId, keys?: readonly string[]) => {
            const command = commandById(id);
            setReadout({ keys: keys ?? command.keys, title: command.title });
        };
        const onKeyDown = (event: KeyboardEvent) => {
            if (event.target instanceof HTMLElement && event.target.closest("input, textarea")) return;
            setPressed((current) => new Set(current).add(event.code));
            const letter = event.code.startsWith("Key") ? event.code.slice(3) : null;
            const tab = tabs.find((t) => t.key === letter);
            if (tab && Date.now() - goRef.current < 1500) {
                goRef.current = 0;
                event.preventDefault();
                return show(`go-${tab.id}`);
            }
            if (event.metaKey && letter === "K") {
                event.preventDefault();
                return show("palette");
            }
            if (event.metaKey && event.code === "Backspace") return show("trash");
            if (event.metaKey || event.ctrlKey || event.altKey) return;
            if (letter === "G") {
                goRef.current = Date.now();
                return setReadout({ go: true });
            }
            if (event.key === "?") return show("shortcuts");
            if (event.key === "!") return show("spam");
            const key = rows.flat().find((k) => k.code === event.code);
            if (!key?.command || key.code === "Backspace" || key.code === "MetaLeft" || key.code === "Digit1") return;
            // Arrows and the rest keep their normal job; only / would open Firefox's quick find.
            if (event.code === "Slash") event.preventDefault();
            show(key.command);
        };
        const onKeyUp = (event: KeyboardEvent) =>
            setPressed((current) => {
                const next = new Set(current);
                next.delete(event.code);
                // macOS swallows key-ups while ⌘ is held, so letting go of ⌘ releases everything.
                return event.key === "Meta" ? new Set() : next;
            });
        addEventListener("keydown", onKeyDown);
        addEventListener("keyup", onKeyUp);
        return () => {
            removeEventListener("keydown", onKeyDown);
            removeEventListener("keyup", onKeyUp);
        };
    }, [onScreen]);

    return (
        <div ref={ref}>
            <div className="flex h-24 flex-col items-center justify-center gap-2 text-center">
                <ReadoutView readout={readout} />
            </div>
            <Fit width={15 * UNIT + 14 * GAP + 42} height={30 + 5 * UNIT + 5 * GAP + 42} className="mt-6">
                <div className="rounded-[22px] border border-white/[0.06] bg-gradient-to-b from-[#121212] to-[#080808] p-5 shadow-[inset_0_1px_0_rgb(255_255_255/0.05),0_40px_100px_-30px_rgb(0_0_0)]">
                    <div className="flex flex-col" style={{ gap: GAP }}>
                        {rows.map((row) => (
                            <div key={row[0]?.code} className="flex" style={{ gap: GAP }}>
                                {row.map((key) => (
                                    <KeyView
                                        key={key.code}
                                        keyDef={key}
                                        down={pressed.has(key.code)}
                                        onPress={() => {
                                            if (!key.command) return;
                                            const command = commandById(key.command);
                                            setReadout({ keys: command.keys, title: command.title });
                                        }}
                                    />
                                ))}
                            </div>
                        ))}
                    </div>
                </div>
            </Fit>
        </div>
    );
}

function ReadoutView({ readout }: { readout: Readout }) {
    if (!readout)
        return (
            <p className="text-[15px] text-muted">
                Press a key. <span className="text-faint">Or click one.</span>
            </p>
        );
    if ("go" in readout)
        return (
            <>
                <p className="text-[28px] font-semibold tracking-[-0.03em]">Go to…</p>
                <p className="font-mono text-[12px] text-muted">
                    {tabs.map((tab) => `${tab.key} ${tab.title}`).join("  ·  ")}
                </p>
            </>
        );
    return (
        <p key={readout.title} className="flex items-center gap-4 text-[28px] font-semibold tracking-[-0.03em]">
            <span className="flex gap-1.5">
                {readout.keys.map((key) => (
                    <kbd
                        key={key}
                        className="flex h-9 min-w-9 items-center justify-center rounded-md border border-line-strong bg-raised px-2 font-mono text-[15px] font-normal text-fg"
                    >
                        {key}
                    </kbd>
                ))}
            </span>
            {readout.title}
        </p>
    );
}

function KeyView({ keyDef: key, down, onPress }: { keyDef: Key; down: boolean; onPress: () => void }) {
    const width = (key.width ?? 1) * UNIT + ((key.width ?? 1) - 1) * GAP;
    const mapped = key.word !== undefined;
    const word = key.label.length > 1;
    return (
        <button
            type="button"
            tabIndex={-1}
            onClick={onPress}
            style={{ width, height: key.short ? 30 : UNIT }}
            className={`relative shrink-0 rounded-[9px] border text-left transition-[transform,background-color,border-color,box-shadow] duration-150 ${
                down
                    ? "translate-y-px border-link/70 bg-[#141a24] shadow-[0_0_0_1px_rgb(82_168_255/0.35),0_0_28px_rgb(10_114_239/0.45)]"
                    : `border-white/[0.07] bg-gradient-to-b from-[#181818] to-[#101010] shadow-[inset_0_1px_0_rgb(255_255_255/0.06),0_2px_0_rgb(0_0_0/0.9)] ${mapped ? "hover:border-white/20" : ""}`
            }`}
        >
            <span
                className={`absolute ${word ? "bottom-1.5 left-2 text-[10px]" : key.short ? "top-1.5 left-2 text-[10px]" : "top-2 left-2.5 text-[15px]"} ${
                    mapped ? "text-fg" : "text-faint"
                } ${word || key.short ? "" : "font-medium"}`}
            >
                {key.label}
            </span>
            {key.word && (
                <span
                    className={`absolute right-2 bottom-1.5 font-mono text-[9.5px] tracking-tight ${down ? "text-link" : "text-muted"} ${word ? "top-1.5 bottom-auto" : ""}`}
                >
                    {key.word}
                </span>
            )}
        </button>
    );
}

export function KeyboardSection() {
    return (
        <Section id="keyboard" className="px-6 py-24 sm:px-12 lg:py-32">
            <Reveal>
                <Heading
                    className="mx-auto max-w-[640px] text-center [&>div]:mx-auto"
                    title="Do everything from the keyboard"
                >
                    <p>
                        Every action has a shortcut. Press ⌘K to search for any command. The palette shows each
                        command's shortcut, so you learn them as you go.
                    </p>
                </Heading>
            </Reveal>
            <Reveal delay={0.1} className="mt-10">
                <Keyboard />
            </Reveal>
        </Section>
    );
}
