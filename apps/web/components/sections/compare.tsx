import { Check, Minus } from "lucide-react";

import { Reveal } from "@/components/reveal";

import { Heading, Section } from "./frame";

const apps = ["bMail", "Apple Mail", "Superhuman", "Gmail on the web"] as const;

/** A cell is a check, a dash or a few words when neither is honest. */
type Cell = boolean | string;

const rows: { feature: string; cells: [Cell, Cell, Cell, Cell] }[] = [
    { feature: "Native Mac app", cells: [true, true, false, false] },
    { feature: "Command palette for every action", cells: [true, false, true, false] },
    { feature: "Open tracking", cells: ["Opens and clicks", false, "Opens", false] },
    { feature: "Gmail and your own domain together", cells: [true, true, false, false] },
    { feature: "Open source", cells: [true, false, false, false] },
    { feature: "Price", cells: ["Free", "Free", "Paid", "Free"] },
];

export function Compare() {
    return (
        <Section id="compare" className="px-6 py-24 sm:px-12 lg:py-32">
            <Reveal>
                <Heading title="How bMail compares" />
            </Reveal>
            <Reveal delay={0.1} className="mt-14 overflow-x-auto">
                <table className="w-full min-w-[720px] border-collapse text-left text-[15px]">
                    <thead>
                        <tr className="border-b border-line">
                            <th className="w-[34%] pb-4 font-normal">
                                <span className="sr-only">Feature</span>
                            </th>
                            {apps.map((app, index) => (
                                <th
                                    key={app}
                                    className={`pb-4 text-[14px] font-medium ${index === 0 ? "rounded-t-xl bg-white/[0.035] px-5 pt-4 text-fg" : "px-4 text-muted"}`}
                                >
                                    {app}
                                </th>
                            ))}
                        </tr>
                    </thead>
                    <tbody>
                        {rows.map((row, rowIndex) => (
                            <tr key={row.feature} className="border-b border-line">
                                <td className="py-4 pr-6 text-fg-2">{row.feature}</td>
                                {row.cells.map((cell, index) => (
                                    <td
                                        key={apps[index]}
                                        className={`py-4 ${index === 0 ? `bg-white/[0.035] px-5 ${rowIndex === rows.length - 1 ? "rounded-b-xl" : ""}` : "px-4"}`}
                                    >
                                        <CellView cell={cell} highlight={index === 0} />
                                    </td>
                                ))}
                            </tr>
                        ))}
                    </tbody>
                </table>
            </Reveal>
        </Section>
    );
}

function CellView({ cell, highlight }: { cell: Cell; highlight: boolean }) {
    if (typeof cell === "string")
        return <span className={`text-[14px] ${highlight ? "text-fg" : "text-muted"}`}>{cell}</span>;
    if (!cell) return <Minus className="size-4 text-line-strong" aria-label="No" />;
    return <Check className={`size-4 ${highlight ? "text-link" : "text-fg-2"}`} strokeWidth={2.5} aria-label="Yes" />;
}
