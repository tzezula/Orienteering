//
//  RunScreen.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import Combine
import SwiftUI
import MapKit

struct RunScreen: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var vm: RunViewModel

    /// Drives the live elapsed-time display.
    @State private var now = Date()
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(route: Route) {
        _vm = StateObject(wrappedValue: RunViewModel(route: route))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Map follows user during the run
            RouteMapView(
                route: vm.route,
                highlightIndex: vm.finished ? nil : vm.currentCheckpointIndex,
                followsUser: true
            )
            .frame(maxHeight: .infinity)

            // Status panel
            VStack(spacing: 8) {
                if vm.waitingForStart {
                    Label("Head to the start point", systemImage: "flag.fill")
                        .font(.headline)
                    Text("Timer starts when you reach the start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if vm.finished {
                    Label("Finished!", systemImage: "checkmark.seal.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                    Text("Total time: \(formatTime(vm.elapsedTime(at: now)))")
                        .font(.title3)
                } else {
                    Text("Checkpoint \(vm.currentCheckpointIndex + 1) of \(vm.route.checkpoints.count)")
                        .font(.headline)
                    Text("Time: \(formatTime(vm.elapsedTime(at: now)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let d = vm.remainingDistances {
                        HStack(spacing: 16) {
                            Label("Next: \(formatDistance(d.toNext))", systemImage: "location.fill")
                            Label("Total: \(formatDistance(d.total))", systemImage: "arrow.triangle.swap")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Text("Get within 10 m of the next checkpoint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationManager.requestPermission()
            locationManager.startTracking()
            vm.startRun()
        }
        .onDisappear {
            locationManager.stopTracking()
        }
        .onReceive(locationManager.$location.compactMap { $0 }) { location in
            vm.updateLocation(location)
        }
        .onReceive(ticker) { date in
            now = date
        }
    }

    // MARK: - Helpers

    private func formatDistance(_ metres: Double) -> String {
        metres >= 1000
            ? String(format: "%.2f km", metres / 1000)
            : String(format: "%.0f m", metres)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let tenths  = Int((t - floor(t)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}
