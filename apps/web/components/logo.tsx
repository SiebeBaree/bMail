import { useId } from "react";

/** The plane's two triangles on a 100 by 100 grid, the same points as LogoMark.swift. The intro draws them too. */
export const plane = {
    wing: [
        [18, 50],
        [82, 22],
        [60, 80],
    ],
    fold: [
        [60, 80],
        [48, 56],
        [82, 22],
    ],
} as const;

const points = (triangle: (typeof plane)[keyof typeof plane]) => triangle.map(([x, y]) => `${x},${y}`).join(" ");

/** The bMail mark: a paper plane on a black squircle, black in both appearances like the app icon. Always sits next to
 * the name, so screen readers skip it. */
export function LogoMark({ size = 22, className }: { size?: number; className?: string }) {
    const gradient = useId();
    return (
        <svg viewBox="0 0 100 100" width={size} height={size} className={className} aria-hidden>
            <defs>
                <radialGradient id={gradient} cx="50%" cy="0%" r="100%">
                    <stop offset="0" stopColor="#1c1c1c" />
                    <stop offset="1" stopColor="#000" />
                </radialGradient>
            </defs>
            <rect width="100" height="100" rx="23" fill={`url(#${gradient})`} />
            <rect
                x="0.75"
                y="0.75"
                width="98.5"
                height="98.5"
                rx="22.5"
                fill="none"
                stroke="#fff"
                strokeOpacity="0.1"
            />
            <polygon points={points(plane.wing)} fill="#fff" />
            <polygon points={points(plane.fold)} fill="#8f8f8f" />
        </svg>
    );
}
