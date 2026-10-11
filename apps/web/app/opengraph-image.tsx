import { ImageResponse } from "next/og";

import { fonts, Mark } from "@/lib/og";
import { site } from "@/lib/site";

export const alt = "bMail, fast native email for your Mac, showing its inbox";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const rows = [
    {
        who: "Jonas Weber",
        subject: "Kickoff deck v3",
        snippet: "v3 is attached. The timeline is slide 3 now.",
        time: "10:24 AM",
        unread: true,
    },
    {
        who: "Priya Raman",
        subject: "Re: Contract for the Halden rebrand",
        snippet: "Signed and attached.",
        time: "9:58 AM",
        unread: true,
    },
    {
        who: "Tomás Ortega",
        subject: "Coffee next week?",
        snippet: "I'm in town Tuesday to Thursday.",
        time: "8:47 AM",
        unread: true,
    },
    {
        who: "Fjord Air",
        subject: "Your trip to Lisbon is confirmed",
        snippet: "Booking K7PQ2M.",
        time: "8:12 AM",
        unread: false,
    },
    {
        who: "Elif Demir",
        subject: "Moodboard feedback",
        snippet: "Love B. Could we try the serif from A?",
        time: "Sat",
        unread: false,
    },
    { who: "Mom", subject: "Sunday dinner", snippet: "Bring the good bread again.", time: "Thu", unread: false },
];

/** The link preview: the hero's words on the left, the inbox running off the right edge. Satori lays out only flexbox. */
export default async function OpenGraphImage() {
    return new ImageResponse(
        <div
            style={{
                display: "flex",
                position: "relative",
                width: "100%",
                height: "100%",
                background: "#000",
                color: "#ededed",
                fontFamily: "Geist",
            }}
        >
            <div
                style={{
                    position: "absolute",
                    inset: 0,
                    display: "flex",
                    backgroundImage:
                        "radial-gradient(circle at 78% 62%, rgba(10,114,239,0.30), rgba(10,114,239,0) 46%), radial-gradient(circle at 60% 95%, rgba(124,58,237,0.16), rgba(124,58,237,0) 40%)",
                }}
            />

            <div
                style={{
                    position: "absolute",
                    left: 72,
                    top: 64,
                    display: "flex",
                    flexDirection: "column",
                    width: 600,
                }}
            >
                <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
                    <Mark size={46} />
                    <span style={{ fontSize: 34, fontWeight: 600, letterSpacing: -1.2 }}>bMail</span>
                </div>
                <div
                    style={{
                        display: "flex",
                        flexDirection: "column",
                        marginTop: 58,
                        fontSize: 86,
                        fontWeight: 600,
                        letterSpacing: -4.2,
                        lineHeight: 0.98,
                    }}
                >
                    <span>Fast, native</span>
                    <span>email for</span>
                    <span style={{ color: "#8f8f8f" }}>your Mac</span>
                </div>
                <div
                    style={{
                        display: "flex",
                        marginTop: 30,
                        fontSize: 27,
                        lineHeight: 1.4,
                        color: "#a1a1a1",
                        width: 520,
                    }}
                >
                    Gmail and your own domain in one app. Free and open source.
                </div>
            </div>

            <div
                style={{
                    position: "absolute",
                    left: 72,
                    bottom: 44,
                    display: "flex",
                    fontFamily: "Geist Mono",
                    fontSize: 22,
                    color: "#6f6f6f",
                }}
            >
                {site.url.replace("https://", "")}
            </div>

            <div
                style={{
                    position: "absolute",
                    left: 700,
                    top: 104,
                    width: 640,
                    height: 600,
                    display: "flex",
                    flexDirection: "column",
                    background: "#0a0a0a",
                    borderRadius: 20,
                    border: "1px solid rgba(255,255,255,0.13)",
                    boxShadow: "0 40px 120px rgba(0,0,0,0.9)",
                    overflow: "hidden",
                    fontSize: 17,
                }}
            >
                <div
                    style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 14,
                        height: 62,
                        padding: "0 22px",
                        background: "#000",
                    }}
                >
                    <div style={{ display: "flex", gap: 9 }}>
                        <div style={{ width: 14, height: 14, borderRadius: 7, background: "#ff5f57" }} />
                        <div style={{ width: 14, height: 14, borderRadius: 7, background: "#febc2e" }} />
                        <div style={{ width: 14, height: 14, borderRadius: 7, background: "#28c840" }} />
                    </div>
                    <div style={{ display: "flex", marginLeft: 10 }}>
                        <Mark size={26} />
                    </div>
                    <span style={{ color: "#2e2e2e", fontSize: 22 }}>/</span>
                    <span style={{ fontWeight: 600 }}>All accounts</span>
                </div>
                <div
                    style={{
                        display: "flex",
                        alignItems: "flex-end",
                        gap: 26,
                        height: 46,
                        padding: "0 24px",
                        background: "#000",
                        borderBottom: "1px solid #1f1f1f",
                        color: "#8f8f8f",
                    }}
                >
                    <div
                        style={{
                            display: "flex",
                            gap: 8,
                            paddingBottom: 12,
                            color: "#ededed",
                            borderBottom: "2px solid #ededed",
                        }}
                    >
                        Inbox<span style={{ fontFamily: "Geist Mono", color: "#8f8f8f" }}>3</span>
                    </div>
                    <div style={{ display: "flex", paddingBottom: 14 }}>Starred</div>
                    <div style={{ display: "flex", paddingBottom: 14 }}>Sent</div>
                    <div style={{ display: "flex", paddingBottom: 14 }}>Done</div>
                    <div style={{ display: "flex", paddingBottom: 14 }}>Tracked</div>
                </div>
                {rows.map((row, index) => (
                    <div
                        key={row.subject}
                        style={{
                            display: "flex",
                            flexDirection: "column",
                            justifyContent: "center",
                            gap: 5,
                            height: 76,
                            padding: "0 22px 0 40px",
                            position: "relative",
                            background: index === 0 ? "#1a1a1a" : "transparent",
                            borderBottom: "1px solid rgba(31,31,31,0.7)",
                        }}
                    >
                        {row.unread && (
                            <div
                                style={{
                                    position: "absolute",
                                    left: 17,
                                    top: 23,
                                    width: 8,
                                    height: 8,
                                    borderRadius: 4,
                                    background: "#52a8ff",
                                }}
                            />
                        )}
                        <div style={{ display: "flex", justifyContent: "space-between" }}>
                            <span
                                style={{
                                    fontWeight: row.unread ? 600 : 400,
                                    color: row.unread ? "#ededed" : "#a1a1a1",
                                }}
                            >
                                {row.who}
                            </span>
                            <span style={{ fontFamily: "Geist Mono", fontSize: 15, color: "#8f8f8f" }}>{row.time}</span>
                        </div>
                        <div style={{ display: "flex", gap: 10, color: "#8f8f8f", whiteSpace: "nowrap" }}>
                            <span style={{ color: row.unread ? "#ededed" : "#a1a1a1" }}>{row.subject}</span>
                            <span>{row.snippet}</span>
                        </div>
                    </div>
                ))}
            </div>
        </div>,
        { ...size, fonts: await fonts() },
    );
}
