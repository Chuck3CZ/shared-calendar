import WidgetKit
import SwiftUI

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: UpcomingEventSnapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(
            date: Date(),
            snapshot: UpcomingEventSnapshot(title: "Táborák", location: "U rybníka", startAt: Date().addingTimeInterval(3600))
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: WidgetDataStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let snapshot = WidgetDataStore.load()
        let now = Date()
        var entries = [Entry(date: now, snapshot: snapshot)]

        let policy: TimelineReloadPolicy
        if let snapshot, snapshot.startAt > now {
            // Once the event's start time passes, ask the system to check
            // back in — by then the app may have written a newer snapshot,
            // or this one should just fall back to the empty state.
            let rollover = snapshot.startAt.addingTimeInterval(60)
            entries.append(Entry(date: rollover, snapshot: nil))
            policy = .after(rollover)
        } else {
            policy = .never
        }

        completion(Timeline(entries: entries, policy: policy))
    }
}

struct SharedCalendarWidgetEntryView: View {
    var entry: Entry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nejbližší akce")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(snapshot.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(snapshot.startAt, style: .relative)
                    .font(.subheadline)
                if let location = snapshot.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Nic naplánováno")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct SharedCalendarWidget: Widget {
    let kind = "SharedCalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SharedCalendarWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Nejbližší akce")
        .description("Ukazuje nejbližší akci, na kterou jdeš.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SharedCalendarWidgetBundle: WidgetBundle {
    var body: some Widget {
        SharedCalendarWidget()
    }
}
