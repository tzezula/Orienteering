//
//  RunViewModel.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import Combine
import CoreLocation

final class RunViewModel: ObservableObject {
    @Published var route: Route
    @Published var currentCheckpointIndex = 0
    @Published var startTime: Date?
    @Published var finished = false
    @Published var waitingForStart = false
    @Published private(set) var currentLocation: CLLocation?

    private var finishTime: Date?
    private let proximityRadius: Double = 10  // metres

    init(route: Route) {
        self.route = route
    }

    func startRun() {
        waitingForStart = true
    }

    /// Distance to the next target and full remaining on-route distance to the finish.
    /// Returns nil when not running (waiting for start or already finished).
    var remainingDistances: (toNext: Double, total: Double)? {
        guard let currentLocation, !waitingForStart, !finished else { return nil }
        let finish = CLLocation(latitude: route.start.latitude, longitude: route.start.longitude)
        // Remaining waypoints: unvisited checkpoints followed by the finish.
        let waypoints: [CLLocation] = route.checkpoints.dropFirst(currentCheckpointIndex).map {
            CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        } + [finish]
        let toNext = currentLocation.distance(from: waypoints[0])
        var total = toNext
        for i in 0..<(waypoints.count - 1) {
            total += waypoints[i].distance(from: waypoints[i + 1])
        }
        return (toNext, total)
    }

    func updateLocation(_ location: CLLocation) {
        currentLocation = location
        if waitingForStart {
            let startLocation = CLLocation(
                latitude:  route.start.latitude,
                longitude: route.start.longitude
            )
            if location.distance(from: startLocation) <= proximityRadius {
                waitingForStart = false
                startTime = Date()
            }
            return
        }

        guard !finished else { return }

        if currentCheckpointIndex < route.checkpoints.count {
            // Check proximity to the next checkpoint in order
            let checkpoint = route.checkpoints[currentCheckpointIndex]
            let target = CLLocation(
                latitude:  checkpoint.coordinate.latitude,
                longitude: checkpoint.coordinate.longitude
            )
            if location.distance(from: target) <= proximityRadius {
                route.checkpoints[currentCheckpointIndex].visited = true
                currentCheckpointIndex += 1
            }
        } else {
            // All checkpoints done — wait for return to start
            checkFinish(location)
        }
    }

    private func checkFinish(_ location: CLLocation) {
        let startLocation = CLLocation(
            latitude:  route.start.latitude,
            longitude: route.start.longitude
        )
        if location.distance(from: startLocation) <= proximityRadius {
            finishTime = Date()
            finished = true
        }
    }

    func elapsedTime(at date: Date = Date()) -> TimeInterval {
        guard let startTime else { return 0 }
        return (finishTime ?? date).timeIntervalSince(startTime)
    }
}
