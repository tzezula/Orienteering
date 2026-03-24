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

/// Invisible UIViewControllerRepresentable that disables the navigation
/// controller's interactive-pop gesture while this screen is on screen,
/// preventing swipe-back from interfering with checkpoint dragging.
private struct PopGestureDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> DisablerViewController {
        DisablerViewController()
    }

    func updateUIViewController(_ uiViewController: DisablerViewController, context: Context) {}

    final class DisablerViewController: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
