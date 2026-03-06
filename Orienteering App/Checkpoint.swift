//
//  Checkpoint.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import CoreLocation

struct Checkpoint: Identifiable {
    let id: Int
    var coordinate: CLLocationCoordinate2D
    var visited: Bool = false
}

struct Route {
    let start: CLLocationCoordinate2D
    var checkpoints: [Checkpoint]
    var totalDistance: Double
}

struct CoordinateRegion {
    let center: CLLocationCoordinate2D
    let latHalf: Double   // half-height in degrees
    let lonHalf: Double   // half-width in degrees
    let rotation: Double  // radians, CCW in the east/north plane

    /// Four corners in SW → SE → NE → NW order.
    /// Uses the standard 2D rotation: dLon = u·cosθ − v·sinθ, dLat = u·sinθ + v·cosθ
    var corners: [CLLocationCoordinate2D] {
        let offsets: [(Double, Double)] = [
            (-lonHalf, -latHalf),   // SW
            ( lonHalf, -latHalf),   // SE
            ( lonHalf,  latHalf),   // NE
            (-lonHalf,  latHalf),   // NW
        ]
        let cosR = cos(rotation), sinR = sin(rotation)
        return offsets.map { u, v in
            CLLocationCoordinate2D(
                latitude:  center.latitude  + u * sinR + v * cosR,
                longitude: center.longitude + u * cosR - v * sinR
            )
        }
    }

    /// Returns a uniformly random coordinate inside this (possibly rotated) rectangle.
    func randomPoint() -> CLLocationCoordinate2D {
        let u = Double.random(in: -lonHalf...lonHalf)
        let v = Double.random(in: -latHalf...latHalf)
        let cosR = cos(rotation), sinR = sin(rotation)
        return CLLocationCoordinate2D(
            latitude:  center.latitude  + u * sinR + v * cosR,
            longitude: center.longitude + u * cosR - v * sinR
        )
    }
}
