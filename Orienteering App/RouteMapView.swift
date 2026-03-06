//
//  RouteMapView.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import SwiftUI
import MapKit

/// A reusable map that draws a route with numbered checkpoint markers.
/// Used by both RoutePreviewScreen and RunScreen.
struct RouteMapView: View {
    let route: Route
    /// The index of the checkpoint the runner must visit next (nil when finished).
    var highlightIndex: Int? = nil
    /// When true the camera starts on the user's position instead of fitting the route.
    var followsUser: Bool = false

    @State private var cameraPosition: MapCameraPosition

    init(route: Route, highlightIndex: Int? = nil, followsUser: Bool = false) {
        self.route = route
        self.highlightIndex = highlightIndex
        self.followsUser = followsUser
        let initial: MapCameraPosition = followsUser
            ? .userLocation(fallback: Self.cameraFitting(route))
            : Self.cameraFitting(route)
        self._cameraPosition = State(initialValue: initial)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            UserAnnotation()

            // Start / Finish
            Marker("Start / Finish", systemImage: "flag.checkered", coordinate: route.start)
                .tint(.green)

            // Checkpoints
            ForEach(Array(route.checkpoints.enumerated()), id: \.element.id) { i, checkpoint in
                Annotation("\(i + 1)", coordinate: checkpoint.coordinate) {
                    ZStack {
                        Circle()
                            .fill(markerColor(index: i, checkpoint: checkpoint))
                            .frame(width: 32, height: 32)
                            .shadow(radius: 2)
                        Text("\(i + 1)")
                            .foregroundStyle(.white)
                            .font(.system(size: 14, weight: .bold))
                    }
                }
            }

            // Route polyline: start → checkpoints → back to start
            let coords = [route.start] + route.checkpoints.map(\.coordinate) + [route.start]
            MapPolyline(coordinates: coords)
                .stroke(.blue, lineWidth: 3)
        }
    }

    // MARK: - Helpers

    private func markerColor(index: Int, checkpoint: Checkpoint) -> Color {
        if checkpoint.visited       { return .green }
        if index == highlightIndex  { return .orange }
        return .red
    }

    /// Returns a camera position that fits all route coordinates with padding.
    private static func cameraFitting(_ route: Route) -> MapCameraPosition {
        let all  = [route.start] + route.checkpoints.map(\.coordinate)
        let lats = all.map(\.latitude)
        let lons = all.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return .automatic
        }
        let center = CLLocationCoordinate2D(
            latitude:  (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max(maxLat - minLat, 0.002) * 1.5,
            longitudeDelta: max(maxLon - minLon, 0.002) * 1.5
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }
}
