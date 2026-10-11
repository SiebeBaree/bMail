"use client";

import { useEffect, useRef, useState } from "react";

import { plane } from "@/components/logo";

type Point = { x: number; y: number; gray: boolean };

type Particle = {
    /** Where it blows in from, off the left edge. */
    sx: number;
    sy: number;
    /** Its dot in the big word. */
    bx: number;
    by: number;
    /** Its dot in the navbar's logo and name. */
    nx: number;
    ny: number;
    /** Bend of the path from the word to the navbar, so the word bursts outward before it regroups. */
    cx: number;
    cy: number;
    gray: boolean;
    delay: number;
    gather: number;
    leave: number;
    amp: number;
    phase: number;
    freq: number;
};

/** Milliseconds from the first frame. The word holds from about 1.8s until HOLD_UNTIL. */
const HOLD_UNTIL = 2150;
const TRAVEL = 1150;
const END = HOLD_UNTIL + 220 + TRAVEL;
const TAU = Math.PI * 2;

const easeOutCubic = (p: number) => 1 - (1 - p) ** 3;
const easeInOutCubic = (p: number) => (p < 0.5 ? 4 * p ** 3 : 1 - (-2 * p + 2) ** 3 / 2);
const clamp01 = (p: number) => Math.min(1, Math.max(0, p));

/**
 * Draws into an offscreen canvas at `density` samples per CSS pixel and returns a point for every covered sample,
 * left to right. A density below 1 gives the coarse dot matrix of the big word; above 1 the fine dots of the navbar.
 */
function sample(
    region: { x: number; y: number; width: number; height: number },
    density: number,
    draw: (context: CanvasRenderingContext2D) => void,
): Point[] {
    const canvas = document.createElement("canvas");
    canvas.width = Math.ceil(region.width * density);
    canvas.height = Math.ceil(region.height * density);
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (!context) return [];
    context.scale(density, density);
    context.translate(-region.x, -region.y);
    draw(context);
    const { data } = context.getImageData(0, 0, canvas.width, canvas.height);
    const points: Point[] = [];
    for (let column = 0; column < canvas.width; column++) {
        for (let row = 0; row < canvas.height; row++) {
            const index = (row * canvas.width + column) * 4;
            if ((data[index + 3] ?? 0) < 128) continue;
            points.push({
                x: region.x + (column + 0.5) / density,
                y: region.y + (row + 0.5) / density,
                gray: (data[index] ?? 0) < 200,
            });
        }
    }
    return points;
}

function setFont(context: CanvasRenderingContext2D, style: CSSStyleDeclaration | { size: number; family: string }) {
    if (style instanceof CSSStyleDeclaration) {
        context.font = `${style.fontWeight} ${style.fontSize} ${style.fontFamily}`;
        context.letterSpacing = style.letterSpacing === "normal" ? "0px" : style.letterSpacing;
    } else {
        context.font = `600 ${style.size}px ${style.family}`;
        context.letterSpacing = `${-0.045 * style.size}px`;
    }
}

/** The big "bMail", centered a little above the middle of the screen. */
function wordPoints(width: number, height: number): { points: Point[]; dot: number } {
    const family = getComputedStyle(document.body).fontFamily;
    const size = Math.min(width * 0.25, height * 0.36, 320);
    const step = Math.min(7, Math.max(3, size / 58));
    const points = sample({ x: 0, y: 0, width, height }, 1 / step, (context) => {
        setFont(context, { size, family });
        const metrics = context.measureText("bMail");
        context.fillStyle = "#fff";
        context.textAlign = "center";
        context.textBaseline = "alphabetic";
        const baseline = height * 0.46 + (metrics.actualBoundingBoxAscent - metrics.actualBoundingBoxDescent) / 2;
        context.fillText("bMail", width / 2, baseline);
    });
    return { points, dot: Math.max(1.4, step * 0.46) };
}

/** The navbar's logo and name exactly where the real ones sit, so the hand-off to the DOM is invisible. */
function brandPoints(density: number): Point[] {
    const logo = document.querySelector<SVGElement>("[data-brand-logo]")?.getBoundingClientRect();
    const text = document.querySelector<HTMLElement>("[data-brand-text]");
    if (!logo || !text) return [];
    const box = text.getBoundingClientRect();
    const style = getComputedStyle(text);
    const region = {
        x: logo.left - 2,
        y: Math.min(logo.top, box.top) - 2,
        width: box.right - logo.left + 8,
        height: Math.max(logo.height, box.height) + 4,
    };
    return sample(region, density, (context) => {
        for (const [triangle, color] of [
            [plane.wing, "#fff"],
            [plane.fold, "#8f8f8f"],
        ] as const) {
            context.beginPath();
            for (const [x, y] of triangle)
                context.lineTo(logo.left + (x / 100) * logo.width, logo.top + (y / 100) * logo.height);
            context.fillStyle = color;
            context.fill();
        }
        setFont(context, style);
        const metrics = context.measureText(text.textContent ?? "");
        const ascent = metrics.fontBoundingBoxAscent;
        const descent = metrics.fontBoundingBoxDescent;
        context.fillStyle = "#fff";
        context.textBaseline = "alphabetic";
        context.fillText(text.textContent ?? "", box.left, box.top + (box.height - ascent - descent) / 2 + ascent);
    });
}

function particles(width: number, height: number, word: Point[], brand: Point[]): Particle[] {
    const count = Math.max(word.length, brand.length);
    const minX = word[0]?.x ?? 0;
    const spanX = Math.max(1, (word.at(-1)?.x ?? width) - minX);
    const centerX = width / 2;
    const centerY = height * 0.46;
    return Array.from({ length: count }, (_, index) => {
        // Both lists run left to right, so mapping by rank keeps neighbours together on the way up.
        const b = word[Math.floor((index * word.length) / count)] ?? { x: centerX, y: centerY, gray: false };
        const n = brand[Math.floor((index * brand.length) / count)] ?? b;
        const across = (b.x - minX) / spanX;
        const outX = b.x - centerX;
        const outY = b.y - centerY;
        const outLength = Math.hypot(outX, outY) || 1;
        const burst = 120 + Math.random() * 260;
        return {
            sx: -40 - Math.random() * width * 0.55,
            sy: b.y + (Math.random() - 0.5) * height * 0.7,
            bx: b.x,
            by: b.y,
            nx: n.x,
            ny: n.y,
            cx: b.x + (outX / outLength) * burst + 60 + Math.random() * 180,
            cy: b.y + (outY / outLength) * burst - 40 - Math.random() * 120,
            gray: n.gray,
            delay: across * 420 + Math.random() * 220,
            gather: 900 + Math.random() * 420,
            leave: Math.random() * 220,
            amp: 20 + Math.random() * 70,
            phase: Math.random() * TAU,
            freq: 3 + Math.random() * 6,
        };
    });
}

/**
 * The page-load animation: dots blow in from the left and settle into "bMail", hold, then burst and regroup as the
 * small logo and name at the top of the navbar. It runs once, stops its frame loop and hands over to the real navbar.
 * Any key, click or scroll skips it.
 */
export function Intro() {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const [phase, setPhase] = useState<"playing" | "fading" | "gone">("playing");

    useEffect(() => {
        const root = document.documentElement;
        const canvas = canvasRef.current;
        const context = canvas?.getContext("2d");
        if (root.dataset.intro !== "play" || !canvas || !context) return;

        let frame = 0;
        let finished = false;
        const finish = () => {
            if (finished) return;
            finished = true;
            cancelAnimationFrame(frame);
            root.dataset.intro = "done";
            setPhase("fading");
        };
        const skipEvents = ["pointerdown", "keydown", "wheel", "touchstart", "resize"] as const;
        for (const event of skipEvents) addEventListener(event, finish, { once: true, passive: true });
        const fallback = setTimeout(finish, 7000);

        const play = async () => {
            await document.fonts.ready;
            if (finished) return;
            const width = innerWidth;
            const height = innerHeight;
            const dpr = Math.min(devicePixelRatio || 1, 2);
            canvas.width = width * dpr;
            canvas.height = height * dpr;
            context.scale(dpr, dpr);

            const word = wordPoints(width, height);
            const brand = brandPoints(dpr);
            if (word.points.length === 0 || brand.length === 0) return finish();
            const dots = particles(width, height, word.points, brand);
            const brandDot = 1.15 / dpr;
            let start: number | null = null;

            const draw = (now: number) => {
                start ??= now;
                const t = now - start;
                const traveling = t > HOLD_UNTIL;
                const settled = (t > 1900 && !traveling) || t > END - 260;
                // Partial clears leave streaks behind fast dots, like gusts. Settled frames clear fully, so the word
                // and the final logo stay crisp.
                context.fillStyle = settled ? "#000" : traveling ? "rgba(0, 0, 0, 0.3)" : "rgba(0, 0, 0, 0.2)";
                context.fillRect(0, 0, width, height);

                const light = new Path2D();
                const gray = new Path2D();
                for (const dot of dots) {
                    let x: number;
                    let y: number;
                    let size: number;
                    let isGray = false;
                    if (!traveling) {
                        const p = clamp01((t - dot.delay) / dot.gather);
                        if (p === 0) continue;
                        const e = easeOutCubic(p);
                        const wind = (1 - e) ** 1.5;
                        x = dot.sx + (dot.bx - dot.sx) * e + Math.cos(dot.phase + p * dot.freq) * dot.amp * 0.35 * wind;
                        y =
                            dot.sy +
                            (dot.by - dot.sy) * e +
                            Math.sin(dot.phase + p * dot.freq) * dot.amp * wind +
                            // One shared wave across the field, so the dots travel in gusts rather than as noise.
                            Math.sin(x * 0.006 - t * 0.005 + dot.by * 0.012) * 110 * wind;
                        size = word.dot;
                    } else {
                        const p = clamp01((t - HOLD_UNTIL - dot.leave) / TRAVEL);
                        const e = easeInOutCubic(p);
                        const a = (1 - e) ** 2;
                        const b = 2 * (1 - e) * e;
                        const c = e * e;
                        const flutter = Math.sin(Math.PI * e) * 26 * Math.sin(dot.phase + e * 8);
                        x = a * dot.bx + b * dot.cx + c * dot.nx + flutter;
                        y = a * dot.by + b * dot.cy + c * dot.ny + flutter * 0.6;
                        size = word.dot + (brandDot - word.dot) * e;
                        isGray = dot.gray && e > 0.6;
                    }
                    const path = isGray ? gray : light;
                    if (size < 1.6) {
                        path.rect(x - size / 2, y - size / 2, size, size);
                    } else {
                        path.moveTo(x + size / 2, y);
                        path.arc(x, y, size / 2, 0, TAU);
                    }
                }
                // Canvas fills, not Array.fill.
                context.fillStyle = "#fff";
                // oxlint-disable-next-line unicorn/no-array-fill-with-reference-type
                context.fill(light);
                context.fillStyle = "#8f8f8f";
                // oxlint-disable-next-line unicorn/no-array-fill-with-reference-type
                context.fill(gray);

                if (t >= END) return finish();
                frame = requestAnimationFrame(draw);
            };
            frame = requestAnimationFrame(draw);
        };
        void play();

        return () => {
            finished = true;
            cancelAnimationFrame(frame);
            clearTimeout(fallback);
            for (const event of skipEvents) removeEventListener(event, finish);
        };
    }, []);

    if (phase === "gone") return null;
    return (
        <canvas
            ref={canvasRef}
            aria-hidden
            data-intro-canvas
            onTransitionEnd={() => setPhase("gone")}
            className={`pointer-events-none fixed inset-0 z-[100] h-dvh w-screen bg-black transition-opacity duration-500 ${phase === "fading" ? "opacity-0" : ""}`}
        />
    );
}
