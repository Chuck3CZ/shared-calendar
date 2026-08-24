import SwiftUI
import MapKit

/// Tapping the static map preview in EventDetailView opens this — a real
/// pinch-to-zoom/pan Map, since the preview itself is a one-shot rendered
/// image (see StaticMapPreview) and can't be interacted with directly.
struct InteractiveMapView: View {
    let latitude: Double
    let longitude: Double
    let title: String

    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double, title: String) {
        self.latitude = latitude
        self.longitude = longitude
        self.title = title
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                Marker(title, coordinate: coordinate)
                    .tint(.red)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openInMaps(latitude: latitude, longitude: longitude, name: title)
                    } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.circle")
                    }
                    .accessibilityLabel("Otevřít v Mapách")
                }
            }
        }
    }
}
