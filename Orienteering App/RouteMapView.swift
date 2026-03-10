//
//  RouteMapView.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import SwiftUI
import CoreLocation

/// A reusable map that draws a route with numbered checkpoint markers.
/// Used by both RoutePreviewScreen and RunScreen.
struct RouteMapView: View {
    let route: Route
    /// The index of the checkpoint the runner must visit next (nil when finished).
    var highlightIndex: Int? = nil
    /// When true the camera starts on the user's position and follows them.
    var followsUser: Bool = false

    var body: some View {
        MLNMapViewWrapper(
            initialCoordinatesToFit: followsUser ? nil : allCoords,
            followsUser: followsUser,
            showsUserLocation: true,
            startCoordinate: route.start,
            checkpoints: route.checkpoints,
            highlightIndex: highlightIndex
        )
    }

    private var allCoords: [CLLocationCoordinate2D] {
        [route.start] + route.checkpoints.map(\.coordinate)
    }
}
