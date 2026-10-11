import { ImageResponse } from "next/og";

import { Mark } from "@/lib/og";

export const size = { width: 180, height: 180 };
export const contentType = "image/png";

/** The home screen icon. Square on purpose: iOS rounds the corners itself. */
export default function AppleIcon() {
    return new ImageResponse(<Mark size={180} rounded={false} />, size);
}
