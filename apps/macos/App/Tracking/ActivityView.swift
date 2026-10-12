import DesignSystem
import MailCore
import MailUI
import SwiftUI

/// What happened to a message you sent: delivery, then every open and click, people and machines apart. Machines are
/// shown hollow and greyed and never counted, because Apple's proxy and security scanners aren't readers.
struct ActivityView: View {
    let message: Message
    let events: [MessageEvent]
    @State private var showsEvents: Bool

    init(message: Message, events: [MessageEvent]) {
        self.message = message
        self.events = events
        // Tracked mail opens on its timeline; that's why you turned tracking on.
        _showsEvents = State(initialValue: message.trackingEnabled)
    }

    private var opens: [MessageEvent] { events.filter { $0.kind == .opened && $0.isReader } }
    private var clicks: [MessageEvent] { events.filter { $0.kind == .clicked && $0.isReader } }
    private var lastActivity: MessageEvent? { events.last { ($0.kind == .opened || $0.kind == .clicked) && $0.isReader } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 28) {
                if let delivered = events.last(where: { $0.kind == .delivered }) {
                    Label { Text("Delivered \(MailDate.short(delivered.occurredAt))") } icon: { StatusDot(.success) }
                }
                if message.trackingEnabled {
                    count(opens.count, "open")
                    count(clicks.count, "click")
                    if let lastActivity {
                        Text("Last activity ") .foregroundStyle(Color.textMuted)
                            + Text(MailDate.short(lastActivity.occurredAt)).foregroundStyle(Color.textPrimary)
                    }
                }
                Spacer()
                Button(showsEvents ? "Hide activity" : "Show activity") { showsEvents.toggle() }
                    .buttonStyle(.ghost)
            }
            .labelStyle(DotLabelStyle())
            .font(.ui)
            .foregroundStyle(Color.textMuted)

            if showsEvents {
                if message.trackingEnabled, events.contains(where: { $0.kind == .opened || $0.kind == .clicked }) {
                    ActivityStrip(sentAt: message.sentAt, events: events)
                        .frame(height: 74)
                }
                Timeline(events: events.reversed())
                if !message.links.isEmpty { LinkTable(links: message.links, events: events) }
            }
        }
        .padding(16)
        .overlay(RoundedRectangle(cornerRadius: Metrics.popoverRadius).strokeBorder(Color.line))
    }

    private func count(_ value: Int, _ noun: String) -> some View {
        Text("\(value)").font(.geist(15, .semibold)).foregroundStyle(Color.textPrimary)
            + Text(" \(noun)\(value == 1 ? "" : "s")").foregroundStyle(Color.textMuted)
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
            configuration.title
        }
    }
}

/// Opens and clicks on one time axis from send to now, one lane each. A single color: the lane label names the series,
/// and hollow marks are the machines.
private struct ActivityStrip: View {
    let sentAt: Date
    let events: [MessageEvent]

    var body: some View {
        let end = max(events.last?.occurredAt ?? .now, sentAt.addingTimeInterval(3600))
        Canvas { context, size in
            let labelWidth: CGFloat = 52
            let lanes: [(MessageEvent.Kind, CGFloat)] = [(.opened, 16), (.clicked, 42)]
            let x = { (date: Date) -> CGFloat in
                labelWidth + 6 + CGFloat(date.timeIntervalSince(sentAt) / end.timeIntervalSince(sentAt)) * (size.width - labelWidth - 12)
            }
            for (kind, y) in lanes {
                context.draw(Text(kind == .opened ? "Opens" : "Clicks").font(.meta).foregroundStyle(Color.textMuted), at: CGPoint(x: 0, y: y), anchor: .leading)
                context.stroke(Path { $0.move(to: CGPoint(x: labelWidth, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(.line), lineWidth: 1)
                for event in events where event.kind == kind {
                    let rect = CGRect(x: x(event.occurredAt) - 5, y: y - 5, width: 10, height: 10)
                    if event.isReader {
                        context.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(.canvas))
                        context.fill(Path(ellipseIn: rect), with: .color(.textPrimary))
                    } else {
                        context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.textFaint), lineWidth: 1.25)
                    }
                }
            }
            for (date, anchor) in [(sentAt, UnitPoint.leading), (end, UnitPoint.trailing)] {
                context.draw(Text(MailDate.short(date)).font(.meta).foregroundStyle(Color.textFaint), at: CGPoint(x: x(date), y: 66), anchor: anchor)
            }
        }
        .accessibilityLabel("\(events.filter { $0.kind == .opened && $0.isReader }.count) opens and \(events.filter { $0.kind == .clicked && $0.isReader }.count) clicks over time")
    }
}

private struct Timeline: View {
    let events: [MessageEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(events) { event in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Group {
                        if event.isReader {
                            Circle().fill(event.kind == .delivered ? Color.success : event.kind.isFailure ? Color.danger : Color.textPrimary)
                        } else {
                            Circle().strokeBorder(Color.textFaint, lineWidth: 1)
                        }
                    }
                    .frame(width: 8, height: 8)
                    Text("\(event.occurredAt.formatted(.dateTime.weekday(.abbreviated))) \(event.occurredAt.formatted(date: .omitted, time: .shortened))")
                        .font(.meta)
                        .frame(width: 96, alignment: .leading)
                    Text(event.kind.title)
                        .font(.uiMedium)
                        .frame(width: 80, alignment: .leading)
                    Text(event.summary)
                        .lineLimit(1)
                }
                .foregroundStyle(event.isReader ? Color.textSecondary : Color.textFaint)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct LinkTable: View {
    let links: [TrackedLink]
    let events: [MessageEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Links").font(.uiSemibold).padding(.bottom, 8)
            ForEach(links, id: \.id) { link in
                let clicks = events.filter { $0.kind == .clicked && $0.url == link.url.absoluteString }
                HStack {
                    Text(link.url.host().map { $0 + link.url.path() } ?? link.url.absoluteString).lineLimit(1)
                    Spacer()
                    Text(label(people: clicks.filter(\.isReader).count, machines: clicks.count(where: { !$0.isReader })))
                        .font(.meta)
                        .foregroundStyle(Color.textMuted)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
    }

    private func label(people: Int, machines: Int) -> String {
        machines > 0 ? "\(people) · \(machines) scanner" : "\(people)"
    }
}
