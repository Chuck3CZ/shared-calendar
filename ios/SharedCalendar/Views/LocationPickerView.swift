import SwiftUI
import MapKit
import CoreLocation

struct LocationPickerView: View {
    let onSelect: (String, CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var searchCompleter = AddressSearchCompleter()
    @State private var searchText: String
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedAddress: String
    @State private var isSelectionPrecise = true
    @State private var cameraPosition: MapCameraPosition

    init(initialAddress: String, initialCoordinate: CLLocationCoordinate2D?, onSelect: @escaping (String, CLLocationCoordinate2D) -> Void) {
        self.onSelect = onSelect
        _searchText = State(initialValue: "")
        _selectedCoordinate = State(initialValue: initialCoordinate)
        _selectedAddress = State(initialValue: initialAddress)

        let region: MKCoordinateRegion
        if let coordinate = initialCoordinate {
            region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        } else {
            // Centered on Czechia — reasonable default without needing location permission.
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 49.8, longitude: 15.5),
                span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
            )
        }
        _cameraPosition = State(initialValue: .region(region))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Hledat adresu nebo místo", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()
                    .onChange(of: searchText) { _, newValue in
                        searchCompleter.update(query: newValue)
                    }

                if !searchCompleter.results.isEmpty {
                    List(searchCompleter.results, id: \.self) { result in
                        Button {
                            Task { await selectCompletion(result) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).foregroundStyle(.primary)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    MapReader { proxy in
                        Map(position: $cameraPosition) {
                            if let selectedCoordinate {
                                Marker(selectedAddress.isEmpty ? "Vybraná poloha" : selectedAddress, coordinate: selectedCoordinate)
                            }
                        }
                        .onTapGesture { point in
                            guard let coordinate = proxy.convert(point, from: .local) else { return }
                            selectedCoordinate = coordinate
                            Task { await reverseGeocode(coordinate) }
                        }
                    }

                    if let selectedCoordinate {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(selectedAddress.isEmpty ? "Vybraná poloha" : selectedAddress)
                                .font(.subheadline)
                            if isSelectionPrecise {
                                Button("Použít tuto polohu") {
                                    onSelect(selectedAddress, selectedCoordinate)
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("Tohle je jen obec/oblast bez čísla popisného. Vyber přesnější místo (adresu s číslem, nebo konkrétní podnik/budovu).")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                        .padding()
                    } else {
                        Text("Vyhledej adresu nebo klepni na mapu")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
            .navigationTitle("Místo akce")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit") { dismiss() }
                }
            }
        }
    }

    @MainActor
    private func selectCompletion(_ completion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: completion)
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first else { return }
        let coordinate = item.placemark.coordinate
        selectedCoordinate = coordinate
        selectedAddress = formattedAddress(from: item.placemark) ?? completion.title
        // A bare place/locality (e.g. just "Dukovany") has no house number and
        // isn't a point of interest either — reject it, only a specific
        // address or a specific venue is precise enough to actually navigate to.
        isSelectionPrecise = item.placemark.subThoroughfare != nil || item.pointOfInterestCategory != nil
        cameraPosition = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        searchText = ""
        searchCompleter.results = []
    }

    @MainActor
    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark: CLPlacemark? = await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                continuation.resume(returning: placemarks?.first)
            }
        }
        if let placemark {
            selectedAddress = formattedAddress(from: placemark) ?? ""
            isSelectionPrecise = placemark.subThoroughfare != nil
        } else {
            isSelectionPrecise = false
        }
    }

    private func formattedAddress(from placemark: CLPlacemark) -> String? {
        let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [street, placemark.locality].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

@MainActor
private final class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 49.8, longitude: 15.5),
            span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 4)
        )
    }

    func update(query: String) {
        completer.queryFragment = query
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.results = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Non-fatal: results just stay whatever they were.
    }
}

#Preview {
    LocationPickerView(initialAddress: "", initialCoordinate: nil) { _, _ in }
}
