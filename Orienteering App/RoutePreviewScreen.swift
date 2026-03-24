//
//  RoutePreviewScreen.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import SwiftUI
import CoreLocation

struct RoutePreviewScreen: View {
    /// Mutable copy of the route so checkpoints can be repositioned by dragging.
    @State private var route: Route

    init(route: Route) {
        _route = State(initialValue: route)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Map ──────────────────────────────────────────────────────────
            MLNMapViewWrapper(
                initialCoordinatesToFit: routeCoords,
                gesturesEnabled: true,
                showsUserLocation: true,
                startCoordinate: route.start,
                checkpoints: route.checkpoints,
                onCheckpointDragged: { index, coord in
                    route.checkpoints[index].coordinate = coord
                    recalcDistance()
                },
                onCheckpointDragEnded: { }
            )
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
        .background(PopGestureDisabler())
    }

    // MARK: - Helpers

    private var routeCoords: [CLLocationCoordinate2D] {
        [route.start] + route.checkpoints.map(\.coordinate) + [route.start]
    }

    private func recalcDistance() {
        var total = 0.0, prev = route.start
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
}

// MARK: - Pop-gesture disabler

/// Invisible UIViewRepresentable that disables the navigation controller's
/// interactive-pop gesture while this screen is on screen, preventing
/// swipe-back from interfering with checkpoint dragging.
///
/// Uses `didMoveToWindow` on a real UIView so the navigation controller is
/// guaranteed to be present in the responder chain.
private struct PopGestureDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> PopGestureDisablerView {
        PopGestureDisablerView()
    }

    func updateUIView(_ uiView: PopGestureDisablerView, context: Context) {}
}

private final class PopGestureDisablerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        setGesture(enabled: window == nil)
    }

    private func setGesture(enabled: Bool) {
        var responder: UIResponder? = self
        while let r = responder {
            if let nc = r as? UINavigationController {
                nc.interactivePopGestureRecognizer?.isEnabled = enabled
                return
            }
            responder = r.next
        }
    }
}
