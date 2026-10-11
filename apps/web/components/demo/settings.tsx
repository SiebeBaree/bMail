import { ChevronDown, ChevronRight, Copy } from "lucide-react";
import type { ReactNode } from "react";

import { MailButton, StatusDot } from "./primitives";

/** Settings > Domains with one domain open (App/Settings/DomainSettings.swift). */

const records = [
    { type: "MX", name: "send", value: "10 feedback-smtp.eu-west-1.amazonses.com" },
    { type: "TXT", name: "send", value: "v=spf1 include:amazonses.com ~all" },
    { type: "TXT", name: "resend._domainkey", value: "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC7p" },
    { type: "MX", name: "@", value: "10 inbound-smtp.eu-west-1.amazonaws.com" },
    { type: "TXT", name: "_dmarc", value: "v=DMARC1; p=none;" },
    { type: "CNAME", name: "t", value: "mail-api.northwind.studio" },
];

export function DomainSettings() {
    return (
        <div className="px-10 pt-14 pb-10">
            <p className="text-[20px] font-semibold tracking-[-0.3px]">Settings</p>
            <div className="mt-12 flex items-center justify-between border-b border-line pb-2.5">
                <span className="text-[15px] font-semibold">Domains</span>
            </div>
            <div className="border-b border-line">
                <div className="flex h-[52px] items-center gap-2.5">
                    <ChevronRight className="size-3 rotate-90 text-muted" />
                    <span className="font-medium">northwind.studio</span>
                    <span className="ml-1.5 flex items-center gap-1.5 text-fg-2">
                        <StatusDot tone="success" />
                        Verified
                    </span>
                    <span className="flex-1" />
                    <span className="text-muted">2 addresses</span>
                </div>
                <div className="pb-5 pl-[22px]">
                    <div className="flex items-center justify-between pb-1.5">
                        <span className="font-semibold">DNS records</span>
                        <MailButton kind="secondary">Check DNS</MailButton>
                    </div>
                    <table className="w-full table-fixed text-[12.5px]">
                        <thead>
                            <tr className="h-[30px] text-left text-muted">
                                <th className="w-[58px] font-normal">Type</th>
                                <th className="w-[136px] font-normal">Name</th>
                                <th className="font-normal">Value</th>
                                <th className="w-[84px] font-normal">Status</th>
                                <th className="w-8">
                                    <span className="sr-only">Copy</span>
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            {records.map((record) => (
                                <tr key={`${record.type}-${record.name}`} className="h-[38px] border-t border-line">
                                    <td>{record.type}</td>
                                    <td className="font-mono text-[12px]">{record.name}</td>
                                    <td className="truncate pr-4 font-mono text-[12px]">{record.value}</td>
                                    <td>
                                        <span className="flex items-center gap-1.5 text-fg-2">
                                            <StatusDot tone="success" />
                                            Verified
                                        </span>
                                    </td>
                                    <td className="text-muted">
                                        <Copy className="size-[11px]" />
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                    <SettingRow title="Catch-all" note="Gets mail sent to addresses that don't exist.">
                        <MailButton kind="secondary">
                            hello@northwind.studio
                            <ChevronDown className="size-3 text-muted" />
                        </MailButton>
                    </SettingRow>
                    <SettingRow title="Tracking host" note="Opens and clicks go through your own domain.">
                        <span className="flex items-center gap-1.5">
                            <StatusDot tone="success" />
                            <span className="font-mono text-[12px]">t.northwind.studio</span>
                        </span>
                    </SettingRow>
                </div>
            </div>
            <div className="mt-4 flex gap-2">
                <span className="flex h-[30px] w-[260px] items-center rounded-md border border-line-strong px-2.5 text-muted">
                    example.com
                </span>
                <MailButton kind="secondary" className="opacity-45">
                    Add domain
                </MailButton>
            </div>
        </div>
    );
}

function SettingRow({ title, note, children }: { title: string; note: string; children: ReactNode }) {
    return (
        <div className="flex items-center gap-4 border-t border-line py-3">
            <span className="flex flex-1 flex-col gap-0.5">
                {title}
                <span className="text-[12px] text-muted">{note}</span>
            </span>
            {children}
        </div>
    );
}
