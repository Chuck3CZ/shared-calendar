import SwiftUI

struct CalendarView: View {
    @State private var selectedDate = Date()
    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingNewEvent = false
    @State private var editingEvent: Event?
    @State private var detailEvent: Event?
    @State private var myProfile: UserProfile?
    @AppStorage("viewAsMember") private var viewAsMember = false

    private var eventsForSelectedDay: [Event] {
        events
            .filter { Calendar.current.isDate($0.startAt, inSameDayAs: selectedDate) }
            .sorted { $0.startAt < $1.startAt }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker("Datum", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)

                List {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else if eventsForSelectedDay.isEmpty {
                        Text("Žádné akce tento den").foregroundStyle(.secondary)
                    } else {
                        ForEach(eventsForSelectedDay) { event in
                            let isMine = myProfile != nil && myProfile?.id == event.ownerId
                            Button {
                                if isMine { detailEvent = event }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(event.title).font(.headline)
                                        Text(event.startAt.formatted(date: .omitted, time: .shortened))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        if let location = event.location {
                                            Text(location).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    if isMine {
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Kalendář")
            .toolbar {
                if !viewAsMember {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showingNewEvent = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingNewEvent, onDismiss: {
                Task { await load() }
            }) {
                NewEventView()
            }
            .sheet(item: $editingEvent, onDismiss: {
                Task { await load() }
            }) { event in
                NewEventView(eventToEdit: event)
            }
            .sheet(item: $detailEvent) { event in
                EventDetailView(
                    event: event,
                    onEdit: {
                        detailEvent = nil
                        editingEvent = event
                    },
                    onDeleted: {
                        Task { await load() }
                    }
                )
            }
            .task {
                await load()
                myProfile = try? await APIClient.shared.fetchMe()
            }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let calendar = Calendar.current
            let from = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            let to = calendar.date(byAdding: .month, value: 3, to: Date()) ?? Date()
            events = try await APIClient.shared.fetchEvents(from: from, to: to)
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst akce: \(error.localizedDescription)"
        }
    }
}

private struct EventDetailView: View {
    let event: Event
    let onEdit: () -> Void
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false
    @State private var showingSlideToDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Akce") {
                    LabeledContent("Název", value: event.title)
                    if let description = event.description, !description.isEmpty {
                        LabeledContent("Popis", value: description)
                    }
                    if let location = event.location, !location.isEmpty {
                        LabeledContent("Místo", value: location)
                    }
                    LabeledContent("Kdy", value: event.startAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                if showingSlideToDelete {
                    Section {
                        SlideToConfirmView(label: "Přejetím přesuneš akci do koše") {
                            await performDelete()
                        }
                        Button("Zrušit mazání") {
                            withAnimation { showingSlideToDelete = false }
                        }
                        .disabled(isDeleting)
                    }
                } else {
                    Section {
                        Button("Upravit") { onEdit() }
                        Button("Smazat", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle("Detail akce")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
            .alert("Opravdu chcete smazat?", isPresented: $showingDeleteConfirm) {
                Button("Zrušit", role: .cancel) {}
                Button("Smazat", role: .destructive) {
                    withAnimation { showingSlideToDelete = true }
                }
            } message: {
                Text("Akce se přesune do koše.")
            }
        }
    }

    private func performDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await APIClient.shared.deleteEvent(id: event.id)
            onDeleted()
            dismiss()
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se smazat akci: \(error.localizedDescription)"
            withAnimation { showingSlideToDelete = false }
        }
    }
}

/// A "slide to confirm" control, similar to iOS's slide-to-power-off, used as
/// a deliberate second confirmation before a destructive action actually runs.
private struct SlideToConfirmView: View {
    let label: String
    let onConfirm: () async -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isConfirming = false
    @State private var trackWidth: CGFloat = 280
    private let thumbSize: CGFloat = 44

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.red.opacity(0.15))
                .frame(height: thumbSize)
            Text(label)
                .font(.subheadline.bold())
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, thumbSize)
            Circle()
                .fill(Color.red)
                .frame(width: thumbSize, height: thumbSize)
                .overlay {
                    if isConfirming {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "chevron.right.2")
                            .foregroundStyle(.white)
                    }
                }
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !isConfirming else { return }
                            let maxOffset = max(trackWidth - thumbSize, 0)
                            dragOffset = min(max(0, value.translation.width), maxOffset)
                        }
                        .onEnded { _ in
                            guard !isConfirming else { return }
                            let maxOffset = max(trackWidth - thumbSize, 0)
                            if maxOffset > 0 && dragOffset > maxOffset * 0.85 {
                                dragOffset = maxOffset
                                isConfirming = true
                                Task { await onConfirm() }
                            } else {
                                withAnimation(.spring) { dragOffset = 0 }
                            }
                        }
                )
        }
        .frame(height: thumbSize)
        .background(
            GeometryReader { proxy in
                Color.clear.onAppear { trackWidth = proxy.size.width }
            }
        )
        .listRowInsets(EdgeInsets())
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

#Preview {
    CalendarView()
}
