//
//  MapLibreMap.swift
//  Orienteering App
//
//  UIViewRepresentable wrapper around MLNMapView (MapLibre Native)
//  serving OSM tiles from OpenFreeMap (no API key required).
//

import MapLibre
import SwiftUI
import CoreLocation

// MARK: - Coordinate conversion proxy

/// Drop-in replacement for MapKit's MapProxy.
/// Exposes coordinate ↔ screen-point conversion once the map view is ready.
final class MLNMapProxy {
    fileprivate(set) weak var mapView: MLNMapView?

    /// Screen point (in the map view's coordinate space) → geo coordinate.
    func screenToCoord(_ point: CGPoint) -> CLLocationCoordinate2D? {
        guard let mv = mapView else { return nil }
        return mv.convert(point, toCoordinateFrom: mv)
    }

    /// Geo coordinate → screen point (in the map view's coordinate space).
    func coordToScreen(_ coord: CLLocationCoordinate2D) -> CGPoint? {
        guard let mv = mapView else { return nil }
        return mv.convert(coord, toPointIn: mv)
    }
}

// MARK: - Custom annotation class (carries the checkpoint index)

final class CheckpointAnnotation: MLNPointAnnotation {
    var checkpointIndex: Int = 0
}

// MARK: - UIViewRepresentable

struct MLNMapViewWrapper: UIViewRepresentable {

    // Free OSM vector tiles, no API key required.
    static let osmStyleURL = URL(string: "https://tiles.openfreemap.org/styles/liberty")!

    // ── Camera ───────────────────────────────────────────────────────────────
    /// When non-nil the wrapper owns the camera (SetupScreen).
    var controlledCenter: CLLocationCoordinate2D? = nil
    var controlledSpan: (lat: Double, lon: Double)? = nil
    /// Fit to these coordinates on first style load (RoutePreviewScreen).
    var initialCoordinatesToFit: [CLLocationCoordinate2D]? = nil
    /// Continuously follow the user (RunScreen).
    var followsUser: Bool = false

    // ── Interaction ──────────────────────────────────────────────────────────
    var gesturesEnabled: Bool = true

    // ── Content ──────────────────────────────────────────────────────────────
    var showsUserLocation: Bool = false
    var startCoordinate: CLLocationCoordinate2D? = nil
    var checkpoints: [Checkpoint] = []
    var highlightIndex: Int? = nil

    // ── Coordinate conversion ────────────────────────────────────────────────
    var proxy: MLNMapProxy? = nil

    // ── Callbacks (RoutePreviewScreen checkpoint drag) ───────────────────────
    var onCheckpointDragged: ((Int, CLLocationCoordinate2D) -> Void)? = nil
    var onCheckpointDragEnded: (() -> Void)? = nil

    // MARK: UIViewRepresentable

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let mv = MLNMapView(frame: .zero, styleURL: Self.osmStyleURL)
        mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mv.delegate = context.coordinator
        mv.isPitchEnabled = false
        mv.logoView.isHidden = true
        mv.attributionButton.isHidden = true

        applyGestures(mv)
        if showsUserLocation || followsUser { mv.showsUserLocation = true }
        if followsUser { mv.userTrackingMode = .follow }

        proxy?.mapView = mv
        context.coordinator.mapView = mv

        // Add checkpoint drag recogniser when needed.
        if onCheckpointDragged != nil {
            let pan = UIPanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleCheckpointPan(_:))
            )
            pan.delegate = context.coordinator
            mv.addGestureRecognizer(pan)
            context.coordinator.checkpointPanGesture = pan
        }
        return mv
    }

    func updateUIView(_ mv: MLNMapView, context: Context) {
        let c = context.coordinator
        c.wrapper = self
        proxy?.mapView = mv

        applyGestures(mv)

        if showsUserLocation || followsUser { mv.showsUserLocation = true }
        mv.userTrackingMode = followsUser ? .follow : .none

        // Camera controlled by SwiftUI (SetupScreen).
        if let center = controlledCenter, let span = controlledSpan {
            mv.userTrackingMode = .none
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: center.latitude - span.lat / 2,
                                           longitude: center.longitude - span.lon / 2),
                ne: CLLocationCoordinate2D(latitude: center.latitude + span.lat / 2,
                                           longitude: center.longitude + span.lon / 2)
            )
            mv.setVisibleCoordinateBounds(bounds, edgePadding: .zero, animated: false)
        }

        guard mv.style != nil else { return }
        c.updateAnnotations(mv)
        c.updatePolyline(mv)
    }

    private func applyGestures(_ mv: MLNMapView) {
        mv.isScrollEnabled  = gesturesEnabled
        mv.isZoomEnabled    = gesturesEnabled
        mv.isRotateEnabled  = gesturesEnabled
    }
}

// MARK: - Coordinator

extension MLNMapViewWrapper {

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {

        var wrapper: MLNMapViewWrapper
        weak var mapView: MLNMapView?

        // Annotation tracking
        var startAnnotation: MLNPointAnnotation?
        var checkpointAnnotations: [CheckpointAnnotation] = []
        var initialFitDone = false

        // Checkpoint drag state
        var checkpointPanGesture: UIPanGestureRecognizer?
        var draggingIndex: Int?

        private let sourceID = "route-source"
        private let layerID  = "route-layer"

        init(_ wrapper: MLNMapViewWrapper) { self.wrapper = wrapper }

        // MARK: - Style loaded

        func mapView(_ mv: MLNMapView, didFinishLoading style: MLNStyle) {
            addPolylineLayer(style)
            updateAnnotations(mv)
            updatePolyline(mv)
            if !initialFitDone, let coords = wrapper.initialCoordinatesToFit, !coords.isEmpty {
                initialFitDone = true
                fitCamera(to: coords, in: mv)
            }
        }

        // MARK: - Annotation view factory

        func mapView(_ mv: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
            if annotation === startAnnotation {
                let id = "start"
                if let v = mv.dequeueReusableAnnotationView(withIdentifier: id) { return v }
                return StartAnnotationView(reuseIdentifier: id)
            }
            if let cp = annotation as? CheckpointAnnotation {
                let id = "checkpoint"
                let v = (mv.dequeueReusableAnnotationView(withIdentifier: id) as? CheckpointAnnotationView)
                    ?? CheckpointAnnotationView(reuseIdentifier: id)
                configure(v, index: cp.checkpointIndex)
                return v
            }
            return nil
        }

        // MARK: - Annotation update

        func updateAnnotations(_ mv: MLNMapView) {
            // Start marker
            if let coord = wrapper.startCoordinate {
                if startAnnotation == nil {
                    let a = MLNPointAnnotation(); a.coordinate = coord
                    startAnnotation = a; mv.addAnnotation(a)
                } else { startAnnotation?.coordinate = coord }
            } else if let a = startAnnotation { mv.removeAnnotation(a); startAnnotation = nil }

            // Checkpoint annotations – grow / shrink list
            let want = wrapper.checkpoints.count
            while checkpointAnnotations.count > want {
                mv.removeAnnotation(checkpointAnnotations.removeLast())
            }
            while checkpointAnnotations.count < want {
                let a = CheckpointAnnotation()
                a.checkpointIndex = checkpointAnnotations.count
                checkpointAnnotations.append(a)
                mv.addAnnotation(a)
            }
            for (i, a) in checkpointAnnotations.enumerated() {
                a.coordinate = wrapper.checkpoints[i].coordinate
                a.checkpointIndex = i
                if let v = mv.view(for: a) as? CheckpointAnnotationView { configure(v, index: i) }
            }
        }

        private func configure(_ v: CheckpointAnnotationView, index i: Int) {
            let cp = wrapper.checkpoints[safe: i]
            v.configure(
                number: i + 1,
                visited: cp?.visited ?? false,
                highlighted: i == wrapper.highlightIndex
            )
        }

        // MARK: - Polyline

        private func addPolylineLayer(_ style: MLNStyle) {
            guard style.source(withIdentifier: sourceID) == nil else { return }
            let src = MLNShapeSource(identifier: sourceID, shape: nil, options: nil)
            style.addSource(src)
            let layer = MLNLineStyleLayer(identifier: layerID, source: src)
            layer.lineColor  = NSExpression(forConstantValue: UIColor.systemBlue)
            layer.lineWidth  = NSExpression(forConstantValue: 3)
            layer.lineCap    = NSExpression(forConstantValue: "round")
            layer.lineJoin   = NSExpression(forConstantValue: "round")
            style.addLayer(layer)
        }

        func updatePolyline(_ mv: MLNMapView) {
            guard let src = mv.style?.source(withIdentifier: sourceID) as? MLNShapeSource else { return }
            var coords = ([wrapper.startCoordinate].compactMap { $0 })
                + wrapper.checkpoints.map(\.coordinate)
                + ([wrapper.startCoordinate].compactMap { $0 })
            src.shape = coords.count >= 2
                ? MLNPolyline(coordinates: &coords, count: UInt(coords.count))
                : nil
        }

        // MARK: - Camera fitting

        func fitCamera(to coords: [CLLocationCoordinate2D], in mv: MLNMapView) {
            let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
            let bounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: lats.min()!, longitude: lons.min()!),
                ne: CLLocationCoordinate2D(latitude: lats.max()!, longitude: lons.max()!)
            )
            mv.setVisibleCoordinateBounds(bounds,
                                          edgePadding: UIEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
                                          animated: false)
        }

        // MARK: - Checkpoint pan gesture

        @objc func handleCheckpointPan(_ g: UIPanGestureRecognizer) {
            guard let mv = mapView else { return }
            let pt = g.location(in: mv)

            switch g.state {
            case .changed:
                guard let idx = draggingIndex else { return }
                let coord = mv.convert(pt, toCoordinateFrom: mv)
                wrapper.onCheckpointDragged?(idx, coord)
                checkpointAnnotations[safe: idx]?.coordinate = coord

            case .ended, .cancelled:
                mv.isScrollEnabled = wrapper.gesturesEnabled
                draggingIndex = nil
                wrapper.onCheckpointDragEnded?()

            default: break
            }
        }

        // MARK: - UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g === checkpointPanGesture, let mv = mapView else { return false }
            let pt = g.location(in: mv)
            for ann in checkpointAnnotations {
                if let v = mv.view(for: ann) {
                    if v.bounds.contains(v.convert(pt, from: mv)) {
                        draggingIndex = ann.checkpointIndex
                        mv.isScrollEnabled = false
                        return true
                    }
                }
            }
            return false
        }

        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { g === checkpointPanGesture }
    }
}

// MARK: - Annotation views

private final class StartAnnotationView: MLNAnnotationView {
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        let iv = UIImageView(frame: bounds)
        iv.contentMode = .scaleAspectFit
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
        iv.image = UIImage(systemName: "flag.checkered", withConfiguration: cfg)?
            .withTintColor(.systemGreen, renderingMode: .alwaysOriginal)
        addSubview(iv)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class CheckpointAnnotationView: MLNAnnotationView {
    private let circle = UIView()
    private let label  = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        circle.frame = bounds
        circle.layer.cornerRadius = 16
        circle.clipsToBounds = true
        layer.shadowRadius  = 2
        layer.shadowOpacity = 0.4
        layer.shadowOffset  = .zero
        addSubview(circle)
        label.frame = bounds
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 14, weight: .bold)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(number: Int, visited: Bool, highlighted: Bool) {
        label.text = "\(number)"
        circle.backgroundColor = visited ? .systemGreen : highlighted ? .systemOrange : .systemRed
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
