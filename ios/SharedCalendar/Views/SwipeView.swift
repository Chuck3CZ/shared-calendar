import SwiftUI

struct SwipeView: View {
    @State private var pending: [Event] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingReviewBanner = false
    @AppStorage("viewAsMember") private var viewAsMember = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewAsMember {
                    Text("Testovací režim člena – swipnutí se nikam neukládá")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                if isShowingReviewBanner {
                    Text("Znovu procházíš všechny akce – nové rozhodnutí přepíše to staré")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                ZStack {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red).padding()
                    } else if pending.isEmpty {
                        ContentUnavailableView(
                            "Žádné nové akce",
                            systemImage: "checkmark.circle",
                            description: Text("Všechno máš probrané")
                        )
                    } else {
                        ForEach(Array(pending.enumerated().reversed()), id: \.element.id) { index, event in
                            SwipeCard(event: event) { status in
                                respond(to: event, status: status)
                            }
                            .zIndex(Double(index))
                            .allowsHitTesting(index == pending.count - 1)
                        }
                    }
                }
                .padding()
                .frame(height: 480)
            }
            .navigationTitle("Objevuj")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await loadReviewAll() }
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .accessibilityLabel("Znovu prozkoumat všechny akce")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Načíst nové akce")
                }
            }
            .refreshable { await load() }
            .onAppear { Task { await load() } }
            .onChange(of: viewAsMember) { Task { await load() } }
        }
    }

    /// Normal queue: only events not yet responded to. This is the default
    /// for every implicit reload (tab switch, pull-to-refresh, the refresh
    /// button) so "review everything again" never comes back on its own.
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        isShowingReviewBanner = false
        do {
            pending = try await APIClient.shared.fetchPending(viewAsMember: viewAsMember)
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst akce: \(error.localizedDescription)"
        }
    }

    /// One-off action from the dedicated toolbar button: pulls in every
    /// event, including already-decided ones, so they can be re-swiped.
    private func loadReviewAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            pending = try await APIClient.shared.fetchReview(viewAsMember: viewAsMember)
            isShowingReviewBanner = true
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = "Nepodařilo se načíst akce: \(error.localizedDescription)"
        }
    }

    private func respond(to event: Event, status: String) {
        pending.removeAll { $0.id == event.id }
        // While testing as a member, the identity is ephemeral: nothing is
        // ever persisted, so it's fully forgotten once the toggle is off.
        guard !viewAsMember else { return }
        Task {
            try? await APIClient.shared.respond(eventId: event.id, status: status)
        }
    }
}

private struct SwipeCard: View {
    let event: Event
    let onDecide: (String) -> Void

    @State private var offset: CGSize = .zero
    @GestureState private var isDragging = false

    private let threshold: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text(event.title)
                .font(.title2.bold())
            Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
            if let location = event.location {
                Label(location, systemImage: "mappin.and.ellipse")
                    .foregroundStyle(.secondary)
            }
            if let description = event.description {
                Text(description).lineLimit(4)
            }
            Spacer()
            HStack {
                Text("Odmítnout").foregroundStyle(.red)
                Spacer()
                Text("Zajímá mě").foregroundStyle(.green)
            }
            .font(.caption.bold())
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 8)
        .overlay(alignment: offset.width > 0 ? .topLeading : .topTrailing) {
            if abs(offset.width) > 20 {
                Text(offset.width > 0 ? "ZAJÍMÁ MĚ" : "ODMÍTNOUT")
                    .font(.headline)
                    .padding(8)
                    .background(offset.width > 0 ? Color.green : Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(20)
                    .opacity(min(abs(offset.width) / threshold, 1))
            }
        }
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { offset = $0.translation }
                .onEnded { value in
                    if value.translation.width > threshold {
                        swipeAway(status: "accepted")
                    } else if value.translation.width < -threshold {
                        swipeAway(status: "rejected")
                    } else {
                        withAnimation(.spring) { offset = .zero }
                    }
                }
        )
    }

    private func swipeAway(status: String) {
        withAnimation(.easeOut) {
            offset = CGSize(width: status == "accepted" ? 600 : -600, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDecide(status)
        }
    }
}

#Preview {
    SwipeView()
}
