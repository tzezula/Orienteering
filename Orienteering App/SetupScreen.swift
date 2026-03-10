//
//  SetupScreen.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import SwiftUI
import CoreLocation

struct SetupScreen: View {
    @StateObject var vm = SetupViewModel()
    @StateObject private var locationManager = LocationManager()

    /// Coordinate-conversion proxy injected into the MapLibre wrapper.
    @State private var mapProxy = MLNMapProxy()

    /// Camera centre (nil = no controlled camera yet; wrapper starts following user).
    @State private var cameraCenter: CLLocationCoordinate2D?
    @State private var cameraLatDelta: Double = 0.05
    @State private var cameraLonDelta: Double = 0.05

    @State private var generatedRoute: Route?
    @State private var showPreview = false

    // ── Drag gesture state ───────────────────────────────────────────────────
    @State private var dragMovesRegion = false
    @State private var dragStartRegionCenter: CLLocationCoordinate2D?
    @State private var dragStartCameraCenter: CLLocationCoordinate2D?

    // ── Rotation / zoom gesture state ────────────────────────────────────────
    @State private var rotationStart: Double?
    @State private var zoomStartLatDelta: Double?
    @State private var zoomStartLonDelta: Double?

    var body: some View {
        VStack(spacing: 0) {
            // ── Map ──────────────────────────────────────────────────────────
            MLNMapViewWrapper(
                controlledCenter: cameraCenter,
                controlledSpan: cameraCenter != nil
                    ? (lat: cameraLatDelta, lon: cameraLonDelta)
                    : nil,
                followsUser: cameraCenter == nil,   // follow until start point is fixed
                gesturesEnabled: false,
                showsUserLocation: true,
                startCoordinate: vm.startPoint,
                proxy: mapProxy
            )
            // Visual region box.
            .overlay { regionOverlay() }
            // Full-screen transparent gesture capture layer.
            .overlay {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { point in
                        guard let coord = mapProxy.screenToCoord(point) else { return }
                        vm.setStartPoint(coord)
                        updateCamera(for: coord)
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { value in
                                if dragStartRegionCenter == nil && dragStartCameraCenter == nil {
                                    dragMovesRegion = isInsideRegion(value.startLocation)
                                    if dragMovesRegion {
                                        dragStartRegionCenter = vm.regionCenter
                                    } else {
                                        dragStartCameraCenter = cameraCenter
                                    }
                                }

                                guard let o  = mapProxy.screenToCoord(.zero),
                                      let rx = mapProxy.screenToCoord(CGPoint(x: 1, y: 0)),
                                      let ry = mapProxy.screenToCoord(CGPoint(x: 0, y: 1))
                                else { return }
                                let lonPerPt = rx.longitude - o.longitude
                                let latPerPt = ry.latitude  - o.latitude

                                let dw = Double(value.translation.width)
                                let dh = Double(value.translation.height)

                                if dragMovesRegion {
                                    guard let base = dragStartRegionCenter else { return }
                                    vm.moveRegion(to: CLLocationCoordinate2D(
                                        latitude:  base.latitude  + latPerPt * dh,
                                        longitude: base.longitude + lonPerPt * dw
                                    ))
                                } else {
                                    guard let base = dragStartCameraCenter else { return }
                                    cameraCenter = CLLocationCoordinate2D(
                                        latitude:  base.latitude  - latPerPt * dh,
                                        longitude: base.longitude - lonPerPt * dw
                                    )
                                }
                            }
                            .onEnded { _ in
                                dragStartRegionCenter = nil
                                dragStartCameraCenter = nil
                            }
                    )
                    .simultaneousGesture(
                        RotationGesture()
                            .onChanged { angle in
                                if rotationStart == nil { rotationStart = vm.regionRotation }
                                vm.setRotation(rotationStart! + angle.radians)
                            }
                            .onEnded { _ in rotationStart = nil }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                if zoomStartLatDelta == nil {
                                    zoomStartLatDelta = cameraLatDelta
                                    zoomStartLonDelta = cameraLonDelta
                                }
                                guard let sLat = zoomStartLatDelta,
                                      let sLon = zoomStartLonDelta,
                                      cameraCenter != nil else { return }
                                cameraLatDelta = (sLat / scale).clamped(to: 0.001...180)
                                cameraLonDelta = (sLon / scale).clamped(to: 0.001...360)
                            }
                            .onEnded { _ in zoomStartLatDelta = nil; zoomStartLonDelta = nil }
                    )
            }
            .frame(maxHeight: .infinity)

            // ── Settings form ────────────────────────────────────────────────
            Form {
                Section("Route Settings") {
                    Stepper("Checkpoints: \(vm.checkpointCount)",
                            value: $vm.checkpointCount, in: 3...20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Distance: \(Int(vm.distance)) m")
                        Slider(value: $vm.distance, in: 500...10_000, step: 250)
                    }
                }
            }
            .frame(height: 165)

            // ── Generate button ──────────────────────────────────────────────
            Button {
                guard let region = vm.selectedRegion, let start = vm.startPoint else { return }
                generatedRoute = RouteGenerator.generate(
                    area: region, start: start,
                    checkpoints: vm.checkpointCount, targetDistance: vm.distance
                )
                showPreview = true
            } label: {
                Text("Generate Route")
                    .frame(maxWidth: .infinity).padding()
                    .background(vm.canGenerateRoute() ? Color.accentColor : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            }
            .disabled(!vm.canGenerateRoute())
            .padding(.bottom)
        }
        .navigationTitle("Setup")
        .navigationDestination(isPresented: $showPreview) {
            if let route = generatedRoute { RoutePreviewScreen(route: route) }
        }
        .onAppear { locationManager.requestPermission(); locationManager.startTracking() }
        .onDisappear { locationManager.stopTracking() }
        .onChange(of: locationManager.location) {
            guard let loc = locationManager.location, vm.startPoint == nil else { return }
            vm.setStartPoint(loc.coordinate)
            updateCamera(for: loc.coordinate)
        }
        .onChange(of: vm.distance) {
            if let c = cameraCenter { updateCamera(for: c) }
        }
    }

    // MARK: - Camera

    private func updateCamera(for center: CLLocationCoordinate2D) {
        let halfSide   = (vm.distance / 2.0) * 1.2
        let latDelta   = (halfSide / 111_000.0) * 3.0
        let lonDelta   = (halfSide / (111_000.0 * cos(center.latitude * .pi / 180.0))) * 3.0
        cameraCenter   = center
        cameraLatDelta = latDelta
        cameraLonDelta = lonDelta
    }

    // MARK: - Region overlay

    @ViewBuilder
    private func regionOverlay() -> some View {
        if let region = vm.selectedRegion {
            let pts = region.corners.compactMap { mapProxy.coordToScreen($0) }
            if pts.count == 4 {
                ZStack {
                    Path { p in
                        p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
                    }
                    .fill(Color.blue.opacity(0.12)).allowsHitTesting(false)

                    Path { p in
                        p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }; p.closeSubpath()
                    }
                    .stroke(Color.blue, lineWidth: 2).allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Hit testing

    private func isInsideRegion(_ screenPoint: CGPoint) -> Bool {
        guard let region = vm.selectedRegion else { return false }
        let pts = region.corners.compactMap { mapProxy.coordToScreen($0) }
        guard pts.count == 4 else { return false }
        return isInsideConvexPolygon(screenPoint, polygon: pts)
    }

    private func isInsideConvexPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        let n = polygon.count; var sign: Bool?
        for i in 0..<n {
            let a = polygon[i], b = polygon[(i + 1) % n]
            let cross = (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
            if abs(cross) > 0.01 {
                let s = cross > 0
                if let existing = sign, existing != s { return false }
                sign = s
            }
        }
        return true
    }
}

// MARK: - Comparable clamp helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
