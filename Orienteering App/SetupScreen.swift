//
//  SetupScreen.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import SwiftUI
import MapKit

struct SetupScreen: View {
    @StateObject var vm = SetupViewModel()
    @StateObject private var locationManager = LocationManager()

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Explicit camera state so we can update the camera during pan / zoom gestures.
    @State private var cameraCenter: CLLocationCoordinate2D?
    @State private var cameraSpan = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)

    @State private var generatedRoute: Route?
    @State private var showPreview = false

    // ── Drag gesture state ───────────────────────────────────────────────────
    /// True when the current drag started inside the region (→ move region).
    /// False means the drag started outside (→ pan map).
    @State private var dragMovesRegion = false
    /// Region centre at the moment the region-drag began.
    @State private var dragStartRegionCenter: CLLocationCoordinate2D?
    /// Camera centre at the moment a map-pan drag began.
    @State private var dragStartCameraCenter: CLLocationCoordinate2D?

    // ── Rotation gesture state ───────────────────────────────────────────────
    @State private var rotationStart: Double?

    // ── Zoom gesture state ───────────────────────────────────────────────────
    @State private var zoomStartSpan: MKCoordinateSpan?

    var body: some View {
        VStack(spacing: 0) {
            // ── Map ──────────────────────────────────────────────────────────
            MapReader { proxy in
                // All built-in gestures are disabled; we implement them ourselves
                // so we can route drag behaviour based on touch location.
                Map(position: $cameraPosition, interactionModes: []) {
                    UserAnnotation()

                    if let start = vm.startPoint {
                        Marker("Start / Finish", systemImage: "flag.fill", coordinate: start)
                            .tint(.green)
                    }
                }
                // Visual region box — hit-testing disabled so gestures reach the overlay.
                .overlay {
                    regionOverlay(proxy: proxy)
                }
                // Full-screen transparent gesture capture layer.
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        // Tap → place / reposition the start point.
                        .onTapGesture { point in
                            guard let coord = proxy.convert(point, from: .local) else { return }
                            vm.setStartPoint(coord)
                            updateCamera(for: coord)
                        }
                        // Single-finger drag:
                        //   • started inside region  → move the region
                        //   • started outside region → pan the map camera
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { value in
                                    // Determine behaviour on the very first event.
                                    if dragStartRegionCenter == nil && dragStartCameraCenter == nil {
                                        dragMovesRegion = isInsideRegion(value.startLocation,
                                                                         proxy: proxy)
                                        if dragMovesRegion {
                                            dragStartRegionCenter = vm.regionCenter
                                        } else {
                                            dragStartCameraCenter = cameraCenter
                                        }
                                    }

                                    // Compute degrees-per-point at the current zoom level.
                                    guard let o  = proxy.convert(.zero,                from: .local),
                                          let rx = proxy.convert(CGPoint(x: 1, y: 0), from: .local),
                                          let ry = proxy.convert(CGPoint(x: 0, y: 1), from: .local)
                                    else { return }
                                    let lonPerPt = rx.longitude - o.longitude
                                    let latPerPt = ry.latitude  - o.latitude  // negative: Y↓ = lat↓

                                    let dw = Double(value.translation.width)
                                    let dh = Double(value.translation.height)

                                    if dragMovesRegion {
                                        guard let base = dragStartRegionCenter else { return }
                                        // Region follows the finger.
                                        vm.moveRegion(to: CLLocationCoordinate2D(
                                            latitude:  base.latitude  + latPerPt * dh,
                                            longitude: base.longitude + lonPerPt * dw
                                        ))
                                    } else {
                                        guard let base = dragStartCameraCenter else { return }
                                        // Camera moves opposite to the drag so the map
                                        // appears to scroll with the finger.
                                        let newCenter = CLLocationCoordinate2D(
                                            latitude:  base.latitude  - latPerPt * dh,
                                            longitude: base.longitude - lonPerPt * dw
                                        )
                                        cameraCenter = newCenter
                                        cameraPosition = .region(
                                            MKCoordinateRegion(center: newCenter, span: cameraSpan)
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    dragStartRegionCenter = nil
                                    dragStartCameraCenter = nil
                                }
                        )
                        // Two-finger rotation → change the region's orientation.
                        // Works regardless of where on the map the gesture starts.
                        .simultaneousGesture(
                            RotationGesture()
                                .onChanged { angle in
                                    if rotationStart == nil { rotationStart = vm.regionRotation }
                                    vm.setRotation(rotationStart! + angle.radians)
                                }
                                .onEnded { _ in rotationStart = nil }
                        )
                        // Pinch → zoom the map camera.
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { scale in
                                    if zoomStartSpan == nil { zoomStartSpan = cameraSpan }
                                    guard let start = zoomStartSpan,
                                          let center = cameraCenter else { return }
                                    let newSpan = MKCoordinateSpan(
                                        latitudeDelta:  (start.latitudeDelta  / scale)
                                            .clamped(to: 0.001...180),
                                        longitudeDelta: (start.longitudeDelta / scale)
                                            .clamped(to: 0.001...360)
                                    )
                                    cameraSpan = newSpan
                                    cameraPosition = .region(
                                        MKCoordinateRegion(center: center, span: newSpan)
                                    )
                                }
                                .onEnded { _ in zoomStartSpan = nil }
                        )
                }
            }
            .frame(maxHeight: .infinity)

            // ── Settings form ────────────────────────────────────────────────
            Form {
                Section("Route Settings") {
                    Stepper(
                        "Checkpoints: \(vm.checkpointCount)",
                        value: $vm.checkpointCount,
                        in: 3...20
                    )

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
                    area: region,
                    start: start,
                    checkpoints: vm.checkpointCount,
                    targetDistance: vm.distance
                )
                showPreview = true
            } label: {
                Text("Generate Route")
                    .frame(maxWidth: .infinity)
                    .padding()
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
            if let route = generatedRoute {
                RoutePreviewScreen(route: route)
            }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startTracking()
        }
        .onDisappear {
            locationManager.stopTracking()
        }
        // Auto-set start from GPS on first fix.
        .onChange(of: locationManager.location) {
            guard let location = locationManager.location, vm.startPoint == nil else { return }
            vm.setStartPoint(location.coordinate)
            updateCamera(for: location.coordinate)
        }
        // Re-frame when the distance (region size) changes.
        .onChange(of: vm.distance) {
            if let center = cameraCenter { updateCamera(for: center) }
        }
    }

    // MARK: - Camera

    /// Updates all camera state atomically and re-frames the map to show the region.
    private func updateCamera(for center: CLLocationCoordinate2D) {
        let halfSide = (vm.distance / 2.0) * 1.2
        let latDelta = (halfSide / 111_000.0) * 3.0
        let lonDelta = (halfSide / (111_000.0 * cos(center.latitude * .pi / 180.0))) * 3.0
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        cameraCenter = center
        cameraSpan   = span
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    // MARK: - Region overlay

    @ViewBuilder
    private func regionOverlay(proxy: MapProxy) -> some View {
        if let region = vm.selectedRegion {
            let pts = region.corners.compactMap { proxy.convert($0, to: .local) }
            if pts.count == 4 {
                ZStack {
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                        p.closeSubpath()
                    }
                    .fill(Color.blue.opacity(0.12))
                    .allowsHitTesting(false)

                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                        p.closeSubpath()
                    }
                    .stroke(Color.blue, lineWidth: 2)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Point-in-region hit test

    /// Returns true if `screenPoint` falls inside the region polygon in screen coordinates.
    private func isInsideRegion(_ screenPoint: CGPoint, proxy: MapProxy) -> Bool {
        guard let region = vm.selectedRegion else { return false }
        let pts = region.corners.compactMap { proxy.convert($0, to: .local) }
        guard pts.count == 4 else { return false }
        return isInsideConvexPolygon(screenPoint, polygon: pts)
    }

    /// Cross-product winding test — works for any convex polygon.
    private func isInsideConvexPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        let n = polygon.count
        var sign: Bool?
        for i in 0..<n {
            let a = polygon[i]
            let b = polygon[(i + 1) % n]
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
