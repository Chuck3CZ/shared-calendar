import SwiftUI
import MapKit
import UIKit

/// A non-interactive map preview rendered once as a static image via
/// `MKMapSnapshotter`, instead of an embedded live `Map`. A live `Map` runs
/// its own continuous rendering/compositing loop even when non-interactive,
/// which is expensive when several are on screen at once (e.g. the whole
/// swipe stack rendering simultaneously) — a static snapshot renders once
/// and just costs a normal image from then on. The `.task(id:)` only
/// re-renders when the coordinate actually changes.
struct StaticMapPreview: View {
    let latitude: Double
    let longitude: Double
    let title: String
    var spanDelta: Double = 0.0008
    var height: CGFloat = 140

    @State private var image: UIImage?

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.secondary.opacity(0.15))
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: "\(latitude),\(longitude),\(spanDelta)") {
            await renderSnapshot()
        }
    }

    private func renderSnapshot() async {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: spanDelta, longitudeDelta: spanDelta)
        )
        options.size = CGSize(width: 400, height: height)
        options.scale = 2
        options.showsBuildings = true

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }

        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        image = renderer.image { _ in
            snapshot.image.draw(at: .zero)
            let pin = UIImage(systemName: "mappin.circle.fill")?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            let point = snapshot.point(for: coordinate)
            let pinSize = CGSize(width: 28, height: 28)
            pin?.draw(in: CGRect(
                x: point.x - pinSize.width / 2,
                y: point.y - pinSize.height,
                width: pinSize.width,
                height: pinSize.height
            ))
        }
    }
}
