/** Fake mail for the app replicas. One person, Mara, with two addresses on her studio's domain and a Gmail account. */

export type Account = { id: string; kind: "domain" | "gmail"; address: string; name: string };

export const accounts = [
    { id: "mara", kind: "domain", address: "mara@northwind.studio", name: "Mara Lindqvist" },
    { id: "hello", kind: "domain", address: "hello@northwind.studio", name: "Northwind Studio" },
    { id: "gmail", kind: "gmail", address: "mara.lindqvist@gmail.com", name: "Mara Lindqvist" },
] as const satisfies readonly Account[];

export type AccountId = (typeof accounts)[number]["id"];

/** The short label the unified inbox shows next to each conversation, like Account.tag in the app. */
export const accountTag = (id: AccountId) => (id === "gmail" ? "gmail" : id);
export const accountById = (id: AccountId) => accounts.find((account) => account.id === id) ?? accounts[0];

export type Person = { name: string; email: string };

export type ActivityEvent = {
    kind: "delivered" | "opened" | "clicked";
    time: string;
    /** Minutes after sending, for the activity strip. */
    at: number;
    /** False for Apple's privacy proxy and security scanners: shown hollow and never counted. */
    reader: boolean;
    summary: string;
};

export type Message = {
    id: string;
    from: Person;
    to: Person[];
    outbound?: boolean;
    time: string;
    snippet: string;
    body: string[];
    attachments?: { name: string; size: string }[];
    delivery?: "Delivered" | "Sent";
    activity?: { events: ActivityEvent[]; links: { url: string; people: number; scanners: number }[] };
};

export type Folder = "inbox" | "done" | "trash";

export type Conversation = {
    id: string;
    account: AccountId;
    subject: string;
    participants: string;
    time: string;
    folder: Folder;
    unread: boolean;
    starred: boolean;
    labels: string[];
    unsubscribe?: boolean;
    messages: Message[];
};

export const labels = ["Clients", "Travel"];

const mara: Person = { name: "Mara Lindqvist", email: "mara@northwind.studio" };
const hello: Person = { name: "Northwind Studio", email: "hello@northwind.studio" };
const maraGmail: Person = { name: "Mara Lindqvist", email: "mara.lindqvist@gmail.com" };
const jonas: Person = { name: "Jonas Weber", email: "jonas@northwind.studio" };
const priya: Person = { name: "Priya Raman", email: "priya@haldencoffee.com" };
const tomas: Person = { name: "Tomás Ortega", email: "tomas.ortega@gmail.com" };
const elif: Person = { name: "Elif Demir", email: "elif@juniper.house" };
const oskar: Person = { name: "Oskar Berg", email: "oskar@juniper.house" };

export const proposalActivity: Message["activity"] = {
    events: [
        { kind: "delivered", time: "Thu 9:03 AM", at: 0, reader: true, summary: "mx.haldencoffee.com accepted it" },
        { kind: "opened", time: "Thu 9:03 AM", at: 1, reader: false, summary: "Apple privacy proxy, on delivery" },
        {
            kind: "clicked",
            time: "Thu 9:04 AM",
            at: 2,
            reader: false,
            summary: "northwind.studio/halden · link scanner",
        },
        { kind: "opened", time: "Thu 9:41 AM", at: 38, reader: true, summary: "Mac · Copenhagen, Denmark" },
        {
            kind: "clicked",
            time: "Thu 9:44 AM",
            at: 41,
            reader: true,
            summary: "northwind.studio/halden · Mac · Copenhagen, Denmark",
        },
        { kind: "opened", time: "Thu 1:12 PM", at: 249, reader: true, summary: "iPhone · Copenhagen, Denmark" },
        { kind: "opened", time: "Thu 4:30 PM", at: 447, reader: true, summary: "Gmail, location hidden by Google" },
        {
            kind: "clicked",
            time: "Thu 4:33 PM",
            at: 450,
            reader: true,
            summary: "cal.northwind.studio/mara · Mac · Copenhagen, Denmark",
        },
    ],
    links: [
        { url: "northwind.studio/halden", people: 1, scanners: 1 },
        { url: "cal.northwind.studio/mara", people: 1, scanners: 0 },
    ],
};

export const conversations: Conversation[] = [
    {
        id: "kickoff",
        account: "mara",
        subject: "Kickoff deck v3",
        participants: "Jonas Weber",
        time: "10:24 AM",
        folder: "inbox",
        unread: true,
        starred: false,
        labels: ["Clients"],
        messages: [
            {
                id: "kickoff-1",
                from: jonas,
                to: [mara],
                time: "Tue",
                snippet: "First pass at the Halden kickoff deck. Timeline is rough, the rest is close.",
                body: ["First pass at the Halden kickoff deck. Timeline is rough, the rest is close."],
            },
            {
                id: "kickoff-2",
                from: mara,
                to: [jonas],
                outbound: true,
                time: "Wed",
                snippet: "Looks good. Move the timeline up front and cut the agency history?",
                body: ["Looks good. Move the timeline up front and cut the agency history?"],
                delivery: "Delivered",
            },
            {
                id: "kickoff-3",
                from: jonas,
                to: [mara],
                time: "10:24 AM",
                snippet: "v3 is attached. The timeline is slide 3 now and launch moved up a week.",
                body: [
                    "Hi Mara,",
                    "v3 is attached. The timeline is slide 3 now and launch moved up a week, so slides 8 to 12 are new. The agency history is gone. Nobody missed it.",
                    "If you're happy with it I'll send it to Priya before lunch tomorrow.",
                    "Jonas",
                ],
                attachments: [{ name: "Halden-kickoff-v3.pdf", size: "4.2 MB" }],
            },
        ],
    },
    {
        id: "contract",
        account: "hello",
        subject: "Re: Contract for the Halden rebrand",
        participants: "Priya Raman",
        time: "9:58 AM",
        folder: "inbox",
        unread: true,
        starred: true,
        labels: ["Clients"],
        messages: [
            {
                id: "contract-1",
                from: hello,
                to: [priya],
                outbound: true,
                time: "Thu",
                snippet: "Contract attached. Shout if legal wants changes.",
                body: ["Contract attached. Shout if legal wants changes."],
                delivery: "Delivered",
            },
            {
                id: "contract-2",
                from: priya,
                to: [hello],
                time: "9:58 AM",
                snippet: "Signed and attached. Legal changed one line in 4.2 about payment terms.",
                body: [
                    "Hi both,",
                    "Signed and attached. Legal changed one line in 4.2 about payment terms, I left a note in the margin. Everything else is as we discussed.",
                    "Can't wait to see the first concepts.",
                    "Priya",
                ],
                attachments: [{ name: "Halden-contract-signed.pdf", size: "312 KB" }],
            },
        ],
    },
    {
        id: "coffee",
        account: "gmail",
        subject: "Coffee next week?",
        participants: "Tomás Ortega",
        time: "8:47 AM",
        folder: "inbox",
        unread: true,
        starred: false,
        labels: [],
        messages: [
            {
                id: "coffee-1",
                from: tomas,
                to: [maraGmail],
                time: "8:47 AM",
                snippet: "I'm in town Tuesday to Thursday. Any morning works, you pick the place.",
                body: [
                    "Hey Mara!",
                    "I'm in town Tuesday to Thursday. Any morning works, you pick the place. Last time was my call and we both know how that went.",
                    "T.",
                ],
            },
        ],
    },
    {
        id: "lisbon",
        account: "gmail",
        subject: "Your trip to Lisbon is confirmed",
        participants: "Fjord Air",
        time: "8:12 AM",
        folder: "inbox",
        unread: false,
        starred: false,
        labels: ["Travel"],
        messages: [
            {
                id: "lisbon-1",
                from: { name: "Fjord Air", email: "trips@fjordair.example" },
                to: [maraGmail],
                time: "8:12 AM",
                snippet: "Booking K7PQ2M. Check-in opens 24 hours before departure.",
                body: [
                    "Booking K7PQ2M",
                    "Copenhagen to Lisbon, Friday 23 October, 07:15. One passenger, one checked bag.",
                    "Check-in opens 24 hours before departure.",
                ],
                attachments: [{ name: "K7PQ2M-itinerary.pdf", size: "88 KB" }],
            },
        ],
    },
    {
        id: "moodboard",
        account: "mara",
        subject: "Moodboard feedback",
        participants: "Elif Demir",
        time: "Sat",
        folder: "inbox",
        unread: false,
        starred: true,
        labels: ["Clients"],
        messages: [
            {
                id: "moodboard-1",
                from: mara,
                to: [elif],
                outbound: true,
                time: "Fri",
                snippet: "Two directions for Juniper. A is quiet, B is loud.",
                body: ["Two directions for Juniper. A is quiet, B is loud."],
                delivery: "Delivered",
            },
            {
                id: "moodboard-2",
                from: elif,
                to: [mara],
                time: "Sat",
                snippet: "Love B. Could we try the serif from A on the headlines?",
                body: [
                    "Love B. Could we try the serif from A on the headlines? Oskar thinks B's sans shouts a bit.",
                    "Otherwise we're ready to go.",
                    "Elif",
                ],
            },
        ],
    },
    {
        id: "weekly",
        account: "gmail",
        subject: "Issue 112: The case for boring software",
        participants: "Paperplane Weekly",
        time: "Sat",
        folder: "inbox",
        unread: false,
        starred: false,
        labels: [],
        unsubscribe: true,
        messages: [
            {
                id: "weekly-1",
                from: { name: "Paperplane Weekly", email: "issues@paperplane.example" },
                to: [maraGmail],
                time: "Sat",
                snippet: "This week: why the dullest stack in the room ships first, and three tools we use daily.",
                body: [
                    "This week: why the dullest stack in the room ships first, and three tools we use every day.",
                    "Plus a reader asks how to say no to a client without losing them.",
                ],
            },
        ],
    },
    {
        id: "statement",
        account: "gmail",
        subject: "Your October statement is ready",
        participants: "Halcyon Bank",
        time: "Fri",
        folder: "inbox",
        unread: false,
        starred: false,
        labels: [],
        messages: [
            {
                id: "statement-1",
                from: { name: "Halcyon Bank", email: "no-reply@halcyon.example" },
                to: [maraGmail],
                time: "Fri",
                snippet: "The statement for your account ending 4417 is in the app.",
                body: ["The statement for your account ending 4417 is in the app."],
            },
        ],
    },
    {
        id: "invoice",
        account: "hello",
        subject: "Invoice 2026-114 paid",
        participants: "Ada Okafor",
        time: "Fri",
        folder: "inbox",
        unread: false,
        starred: false,
        labels: [],
        messages: [
            {
                id: "invoice-1",
                from: { name: "Ada Okafor", email: "ada@lumenpress.example" },
                to: [hello],
                time: "Fri",
                snippet: "Paid this morning. Thanks for turning it around so fast.",
                body: ["Paid this morning. Thanks for turning it around so fast.", "Ada"],
            },
        ],
    },
    {
        id: "dinner",
        account: "gmail",
        subject: "Sunday dinner",
        participants: "Mom",
        time: "Thu",
        folder: "inbox",
        unread: false,
        starred: false,
        labels: [],
        messages: [
            {
                id: "dinner-1",
                from: { name: "Mom", email: "birgitta.lindqvist@gmail.com" },
                to: [maraGmail],
                time: "Thu",
                snippet: "Bring the good bread again. Your father still talks about it.",
                body: ["Bring the good bread again. Your father still talks about it.", "Love, Mom"],
            },
        ],
    },
    {
        id: "intro",
        account: "mara",
        subject: "Intro: Mara, meet Sofia",
        participants: "Kai Nakamura",
        time: "Thu",
        folder: "inbox",
        unread: false,
        starred: false,
        labels: [],
        messages: [
            {
                id: "intro-1",
                from: { name: "Kai Nakamura", email: "kai@kiln.example" },
                to: [mara],
                time: "Thu",
                snippet: "Sofia runs brand at Tessel and is looking for a studio for their relaunch.",
                body: [
                    "Sofia runs brand at Tessel and is looking for a studio for their relaunch. I told her you're the best I know. Over to you two.",
                    "Kai",
                ],
            },
        ],
    },
    {
        id: "shipped",
        account: "gmail",
        subject: "Your order has shipped",
        participants: "Studio Supply Co.",
        time: "Wed",
        folder: "inbox",
        unread: false,
        starred: false,
        labels: [],
        messages: [
            {
                id: "shipped-1",
                from: { name: "Studio Supply Co.", email: "orders@studiosupply.example" },
                to: [maraGmail],
                time: "Wed",
                snippet: "Two A2 cutting mats and a steel ruler are on the way.",
                body: ["Two A2 cutting mats and a steel ruler are on the way. Expect them Friday."],
            },
        ],
    },
    {
        id: "proposal",
        account: "hello",
        subject: "Proposal for the Halden rebrand",
        participants: "Priya Raman",
        time: "Thu",
        folder: "done",
        unread: false,
        starred: false,
        labels: ["Clients"],
        messages: [
            {
                id: "proposal-1",
                from: hello,
                to: [priya],
                outbound: true,
                time: "Thu",
                snippet: "Here's the proposal. Scope, timeline and price are all on one page.",
                body: [
                    "Hi Priya,",
                    "Here's the proposal: northwind.studio/halden. Scope, timeline and price are all on one page.",
                    "If it looks right, grab a slot at cal.northwind.studio/mara and we'll walk through it.",
                    "Mara",
                ],
                delivery: "Delivered",
                activity: proposalActivity,
            },
        ],
    },
    {
        id: "juniper",
        account: "mara",
        subject: "Juniper site, round two",
        participants: "Oskar Berg",
        time: "Wed",
        folder: "done",
        unread: false,
        starred: false,
        labels: ["Clients"],
        messages: [
            {
                id: "juniper-1",
                from: mara,
                to: [oskar],
                outbound: true,
                time: "Wed",
                snippet: "Round two is live on staging. I kept your nav and rebuilt the rest.",
                body: ["Oskar,", "Round two is live on staging. I kept your nav and rebuilt the rest.", "Mara"],
                delivery: "Delivered",
                activity: {
                    events: [
                        { kind: "delivered", time: "Wed 2:10 PM", at: 0, reader: true, summary: "Delivered" },
                        {
                            kind: "opened",
                            time: "Wed 2:10 PM",
                            at: 1,
                            reader: false,
                            summary: "Security scanner, on delivery",
                        },
                        { kind: "opened", time: "Wed 3:02 PM", at: 52, reader: true, summary: "Mac · Oslo, Norway" },
                    ],
                    links: [],
                },
            },
        ],
    },
];
