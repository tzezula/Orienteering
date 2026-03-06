//
//  RouteGenerator.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import CoreLocation

struct RouteGenerator {

    /// Generates a route by randomly placing `checkpoints` inside `area`,
    /// ordering them with a nearest-neighbour heuristic, and computing the
    /// actual total distance (start → all checkpoints → start).
    static func generate(
        area: CoordinateRegion,
        start: CLLocationCoordinate2D,
        checkpoints: Int,
        targetDistance: Double
    ) -> Route {

        // 1. Random points inside the (possibly rotated) region
        var points: [CLLocationCoordinate2D] = []
        for _ in 0..<checkpoints {
            points.append(area.randomPoint())
        }

        // 2. Nearest-neighbour ordering (greedy TSP)
        var ordered: [CLLocationCoordinate2D] = []
        var remaining = points
        var current = start

        while !remaining.isEmpty {
            let nearest = remaining.min { dist($0, current) < dist($1, current) }!
            ordered.append(nearest)
            remaining.removeAll { $0.latitude == nearest.latitude && $0.longitude == nearest.longitude }
            current = nearest
        }

        // 3. Compute actual round-trip distance
        var total = 0.0
        var prev = start
        for coord in ordered {
            total += dist(prev, coord)
            prev = coord
        }
        total += dist(prev, start)

        let checkpointObjects = ordered.enumerated().map { i, coord in
            Checkpoint(id: i, coordinate: coord)
        }

        return Route(start: start, checkpoints: checkpointObjects, totalDistance: total)
    }

    private static func dist(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
