//
//  SetupViewModel.swift
//  Orienteering App
//
//  Created by Tomas Zezula on 19.12.2025.
//

import Combine
import CoreLocation

final class SetupViewModel: ObservableObject {
    @Published var startPoint: CLLocationCoordinate2D?
    /// Centre of the allowed route region.
    @Published var regionCenter: CLLocationCoordinate2D?
    /// Orientation of the region rectangle, in radians CCW.
    @Published var regionRotation: Double = 0
    @Published var distance: Double = 2500 {
        didSet { if let rc = regionCenter { moveRegion(to: rc) } }
    }
    @Published var checkpointCount: Int = 5

    /// Bounding rectangle centred on `regionCenter`, sized to contain a route
    /// of roughly `distance` metres (20 % padding per side), rotated by `regionRotation`.
    var selectedRegion: CoordinateRegion? {
        guard let center = regionCenter else { return nil }
        let halfSide = (distance / 2.0) * 1.2
        let latHalf = halfSide / 111_000.0
        let lonHalf = halfSide / (111_000.0 * cos(center.latitude * .pi / 180.0))
        return CoordinateRegion(center: center, latHalf: latHalf, lonHalf: lonHalf, rotation: regionRotation)
    }

    /// Sets the start point and resets the region centre to the same location.
    func setStartPoint(_ coord: CLLocationCoordinate2D) {
        startPoint = coord
        regionCenter = coord
    }

    /// Moves the region centre, clamping so `startPoint` always remains inside the
    /// (possibly rotated) rectangle.
    func moveRegion(to newCenter: CLLocationCoordinate2D) {
        guard let sp = startPoint else { return }
        let halfSide = (distance / 2.0) * 1.2
        let latHalf = halfSide / 111_000.0
        let lonHalf = halfSide / (111_000.0 * cos(newCenter.latitude * .pi / 180.0))

        // Offset of the start point from the proposed new centre.
        let dLon = sp.longitude - newCenter.longitude
        let dLat = sp.latitude  - newCenter.latitude

        // Inverse rotation (world → local rectangle frame).
        // From dLon = u·cosθ − v·sinθ, dLat = u·sinθ + v·cosθ  ⟹
        //   u = dLon·cosθ + dLat·sinθ
        //   v = −dLon·sinθ + dLat·cosθ
        let cosR = cos(regionRotation), sinR = sin(regionRotation)
        let u =  dLon * cosR + dLat * sinR
        let v = -dLon * sinR + dLat * cosR

        // Clamp so start stays inside the half-extents.
        let uc = max(-lonHalf, min(lonHalf, u))
        let vc = max(-latHalf, min(latHalf, v))

        // Forward rotation back to world offsets.
        let worldLon = uc * cosR - vc * sinR
        let worldLat = uc * sinR + vc * cosR

        regionCenter = CLLocationCoordinate2D(
            latitude:  sp.latitude  - worldLat,
            longitude: sp.longitude - worldLon
        )
    }

    /// Sets the region rotation angle and re-clamps the centre so the start
    /// point remains inside the newly oriented rectangle.
    func setRotation(_ angle: Double) {
        regionRotation = angle
        if let center = regionCenter { moveRegion(to: center) }
    }

    func canGenerateRoute() -> Bool {
        startPoint != nil
    }
}
