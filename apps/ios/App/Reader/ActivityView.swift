import DesignSystem
import MailCore
import MailUI
import SwiftUI

/// What happened to a message you tracked: delivery, then every open and click, people and machines apart. Machines are
/// hollow and grey and never counted, because Apple's proxy and security scanners aren't readers.
struct ActivityView: View {
    let message: Message
    let events: [MessageEvent]
    @State private var showsEvents = true

    private var opens: [MessageEvent] { events.filter { $0.kind == .opened && $0.isReader } }
    private var clicks: [MessageEvent] { events.filter { $0.kind == .clicked && $0.isReader } }
    private var lastActivity: MessageEvent? { events.last { ($0.kind == .opened || $0.kind == .clicked) && $0.isReader } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showsEvents.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    count(opens.count, "open")
                    count(clicks.count, "click")
                    Spacer(minLength: 0)
                    if let lastActivity {
                        Text(MailDate.short(lastActivity.occurredAt)).font(.phoneMono(13)).foregroundStyle(Color.textMuted)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textMuted)
                        .rotationEffect(.degrees(showsEvents ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(opens.count) opens, \(clicks.count) clicks")
            .accessibilityHint(showsEvents ? "Hides the activity" : "Shows the activity")

            if showsEvents {
                VStack(alignment: .leading, spacing: 0) {
                    if events.isEmpty {
                        Text("Nothing yet. Opens and clicks show up here as they happen.")
                            .font(.phone(14))
                            .foregroundStyle(Color.textMuted)
                            .padding(.vertical, 6)
                    }
                    ForEach(events.reversed()) { event in
                        EventRow(event: event)
                    }
                    if !message.links.isEmpty {
                        LinkTable(links: message.links, events: events).padding(.top, 12)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line))
    }

    private func count(_ value: Int, _ noun: String) -> some View {
        Text("\(Text("\(value)").font(.phone(17, .semibold)).foregroundStyle(Color.textPrimary)) \(Text(value == 1 ? noun : noun + "s").font(.phone(15)).foregroundStyle(Color.textMuted))")
    }
}

private struct EventRow: View {
    let event: MessageEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if event.isReader {
                    Circle().fill(event.kind == .delivered ? Color.success : event.kind.isFailure ? Color.danger : Color.textPrimary)
                } else {
                    Circle().strokeBorder(Color.textFaint, lineWidth: 1)
                }
            }
            .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.kind.title).font(.phone(15, .medium))
                    Spacer(minLength: 8)
                    Text(time).font(.phoneMono(12))
                }
                if !event.summary.isEmpty {
                    Text(event.summary).font(.phone(13)).lineLimit(2)
                }
            }
        }
        .foregroundStyle(event.isReader ? Color.textSecondary : Color.textFaint)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var time: String {
        "\(event.occurredAt.formatted(.dateTime.weekday(.abbreviated))) \(event.occurredAt.formatted(date: .omitted, time: .shortened))"
    }
}

private struct LinkTable: View {
    let links: [TrackedLink]
    let events: [MessageEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Links").font(.phone(14, .semibold)).padding(.bottom, 4)
            ForEach(links, id: \.id) { link in
                let clicks = events.filter { $0.kind == .clicked && $0.url == link.url.absoluteString }
                HStack {
                    Text(link.url.host().map { $0 + link.url.path() } ?? link.url.absoluteString)
                        .font(.phone(14))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(label(people: clicks.filter(\.isReader).count, machines: clicks.count(where: { !$0.isReader })))
                        .font(.phoneMono(12))
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
