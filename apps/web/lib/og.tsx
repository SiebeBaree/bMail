import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { plane } from "@/components/logo";

/** Shared by the generated images: the brand mark as plain SVG and Geist from the geist package. Satori can't read
 * variable fonts or woff2, so these are the static TTFs. */

const points = (triangle: (typeof plane)[keyof typeof plane]) => triangle.map(([x, y]) => `${x},${y}`).join(" ");

export function Mark({ size, rounded = true }: { size: number; rounded?: boolean }) {
    return (
        <svg width={size} height={size} viewBox="0 0 100 100">
            <rect width="100" height="100" rx={rounded ? 23 : 0} fill="#0b0b0b" />
            {rounded && (
                <rect
                    x="0.75"
                    y="0.75"
                    width="98.5"
                    height="98.5"
                    rx="22.5"
                    fill="none"
                    stroke="#ffffff"
                    strokeOpacity="0.14"
                    strokeWidth="1.5"
                />
            )}
            <polygon points={points(plane.wing)} fill="#ffffff" />
            <polygon points={points(plane.fold)} fill="#8f8f8f" />
        </svg>
    );
}

const font = (file: string) => readFile(join(process.cwd(), "node_modules/geist/dist/fonts", file));

export async function fonts() {
    const [regular, semibold, mono] = await Promise.all([
        font("geist-sans/Geist-Regular.ttf"),
        font("geist-sans/Geist-SemiBold.ttf"),
        font("geist-mono/GeistMono-Regular.ttf"),
    ]);
    return [
        { name: "Geist", data: regular, weight: 400 as const },
        { name: "Geist", data: semibold, weight: 600 as const },
        { name: "Geist Mono", data: mono, weight: 400 as const },
    ];
}
