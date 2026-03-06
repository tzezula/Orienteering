//
//  RoutePreviewScreen.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import SwiftUI
import MapKit

struct RoutePreviewScreen: View {
    /// Mutable copy of the route so checkpoints can be repositioned by dragging.
    @State private var route: Route
    @State private var cameraPosition: MapCameraPosition

    /// Index of the checkpoint currently being dragged, nil when idle.
    @State private var draggingIndex: Int?
    /// Coordinate of that checkpoint at the moment the drag began.
    @State private var dragStartCoord: CLLocationCoordinate2D?

    init(route: Route) {
        _route          = State(initialValue: route)
        _cameraPosition = State(initialValue: Self.cameraFitting(route))
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Map ──────────────────────────────────────────────────────────
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()

                    Marker("Start / Finish", systemImage: "flag.checkered", coordinate: route.start)
                        .tint(.green)

                    // Draggable checkpoint annotations
                    ForEach(Array(route.checkpoints.enumerated()), id: \.element.id) { i, checkpoint in
                        Annotation("\(i + 1)", coordinate: checkpoint.coordinate) {
                            draggableMarker(index: i, proxy: proxy)
                        }
                    }

                    // Live polyline: start → checkpoints → back to start
                    MapPolyline(coordinates: routeCoords)
                        .stroke(.blue, lineWidth: 3)
                }
            }
            .frame(maxHeight: .infinity)

            // ── Stats & actions ──────────────────────────────────────────────
            VStack(spacing: 4) {
                HStack(spacing: 24) {
                    Label("\(route.checkpoints.count) checkpoints", systemImage: "mappin.circle")
                    Label("\(Int(route.totalDistance)) m", systemImage: "figure.walk")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

                Text("Drag checkpoints to adjust their positions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                NavigationLink("Start Run") {
                    RunScreen(route: route)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Route Preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Draggable marker

    private func draggableMarker(index i: Int, proxy: MapProxy) -> some View {
        let isDragging = draggingIndex == i
        return ZStack {
            Circle()
                .fill(isDragging ? Color.orange : Color.red)
                .frame(width: 32, height: 32)
                .shadow(radius: isDragging ? 8 : 2)
            Text("\(i + 1)")
                .foregroundStyle(.white)
                .font(.system(size: 14, weight: .bold))
        }
        .scaleEffect(isDragging ? 1.25 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isDragging)
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    // Capture state on first event of this drag.
                    if draggingIndex == nil {
                        draggingIndex  = i
                        dragStartCoord = route.checkpoints[i].coordinate
                    }
                    guard draggingIndex == i,
                          let base = dragStartCoord,
                          let o    = proxy.convert(.zero,                from: .local),
                          let rx   = proxy.convert(CGPoint(x: 1, y: 0), from: .local),
                          let ry   = proxy.convert(CGPoint(x: 0, y: 1), from: .local)
                    else { return }

                    let lonPerPt = rx.longitude - o.longitude
                    let latPerPt = ry.latitude  - o.latitude  // negative: Y↓ = lat↓

                    route.checkpoints[i].coordinate = CLLocationCoordinate2D(
                        latitude:  base.latitude  + latPerPt * Double(value.translation.height),
                        longitude: base.longitude + lonPerPt * Double(value.translation.width)
                    )
                    recalcDistance()
                }
                .onEnded { _ in
                    draggingIndex  = nil
                    dragStartCoord = nil
                }
        )
    }

    // MARK: - Helpers

    private var routeCoords: [CLLocationCoordinate2D] {
        [route.start] + route.checkpoints.map(\.coordinate) + [route.start]
    }

    private func recalcDistance() {
        var total = 0.0
        var prev  = route.start
        for cp in route.checkpoints {
            total += dist(prev, cp.coordinate)
            prev   = cp.coordinate
        }
        total += dist(prev, route.start)
        route.totalDistance = total
    }

    private func dist(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

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
