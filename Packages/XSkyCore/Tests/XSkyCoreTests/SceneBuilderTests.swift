import Foundation
import Testing

@testable import XSkyCore

@Suite("Scene building and interaction")
struct SceneBuilderTests {
    let store = CatalogTestSupport.store

    private func viewport(
        raHours: Double, decDegrees: Double, scale: Double = 0.05,
        width: Double = 1024, height: Double = 768,
        orientation: ChartOrientation = .normal
    ) -> ChartViewport {
        ChartViewport(
            center: EquatorialCoordinate(
                rightAscension: Radians(hours: raHours),
                declination: Radians(degrees: decDegrees)),
            degreesPerPoint: scale,
            sizeInPoints: Size2D(width: width, height: height),
            orientation: orientation)
    }

    private func snapshot(
        _ vp: ChartViewport, settings: ChartSettings = ChartSettings()
    ) -> RenderSnapshot {
        ChartSceneBuilder(store: store).buildSnapshot(
            viewport: vp, settings: settings, labels: [], selection: nil,
            generation: 1)
    }

    private func contains(
        _ snapshot: RenderSnapshot, hr: Int
    ) -> RenderedStar? {
        snapshot.stars.first { star in
            guard let object = store.object(star.objectID) else { return false }
            if case .ybs(let n, _, _, _, _) = object.identity {
                return n == hr
            }
            return false
        }
    }

    private func contains(
        _ snapshot: RenderSnapshot, ngc: Int
    ) -> RenderedObject? {
        snapshot.objects.first { rendered in
            guard let object = store.object(rendered.objectID) else {
                return false
            }
            if case .rngc(let n, let sub, _) = object.identity {
                return n == ngc && sub == nil
            }
            return false
        }
    }

    /// The Orion reference view must contain its major stars with the
    /// correct chart orientation: north up, RA increasing to the left.
    @Test func orionReferenceView() {
        let vp = viewport(raHours: 5.6, decDegrees: 0)
        var settings = ChartSettings()
        settings.showBoundaries = true
        settings.showOutlines = true
        let snap = snapshot(vp, settings: settings)

        let betelgeuse = try! #require(contains(snap, hr: 2061))
        let rigel = try! #require(contains(snap, hr: 1713))
        let m42 = try! #require(contains(snap, ngc: 1976))

        // Betelgeuse (RA 5h55m, +7.4) is north of and east of Rigel
        // (RA 5h14m, -8.2): higher RA -> smaller x, higher dec -> smaller y
        #expect(betelgeuse.position.x < rigel.position.x)
        #expect(betelgeuse.position.y < rigel.position.y)
        // M42 sits in the sword, south of the belt
        #expect(m42.position.y > betelgeuse.position.y)

        #expect(!snap.gridPaths.isEmpty)
        #expect(!snap.boundaryPaths.isEmpty)
        #expect(!snap.outlinePaths.isEmpty)
    }

    @Test func m31ReferenceView() {
        let vp = viewport(raHours: 0.712, decDegrees: 41.27)
        let snap = snapshot(vp)
        let m31 = try! #require(contains(snap, ngc: 224))
        // near the center of the view
        #expect(abs(m31.position.x - 512) < 60)
        #expect(abs(m31.position.y - 384) < 60)
        // companions M32 and M110
        #expect(contains(snap, ngc: 221) != nil)
        #expect(contains(snap, ngc: 205) != nil)
    }

    @Test func downunderFlipsOrientation() {
        let vp = viewport(raHours: 5.6, decDegrees: 0)
        let flipped = viewport(
            raHours: 5.6, decDegrees: 0, orientation: .downunder)
        let a = try! #require(contains(snapshot(vp), hr: 2061)).position
        let b = try! #require(contains(snapshot(flipped), hr: 2061)).position
        #expect(abs((1024 - a.x) - b.x) < 1e-6)
        #expect(abs((768 - a.y) - b.y) < 1e-6)
    }

    @Test func catalogAndMagnitudeFiltersApply() {
        let vp = viewport(raHours: 5.6, decDegrees: 0)
        var settings = ChartSettings()
        settings.setVisible(false, catalog: .ybs)
        #expect(snapshot(vp, settings: settings).stars.isEmpty)

        var brightOnly = ChartSettings()
        brightOnly.stellarLimitingMagnitude = 1.0
        let snap = snapshot(vp, settings: brightOnly)
        #expect(!snap.stars.isEmpty)
        for star in snap.stars {
            let object = try! #require(store.object(star.objectID))
            #expect((object.magnitude ?? 0) <= 1.0)
        }
    }

    /// Tap selection prefers a non-stellar object over a coincident star.
    @Test func hitTestPrefersNonStellarObjects() {
        let vp = viewport(raHours: 5.588, decDegrees: -5.39, scale: 0.01)
        let snap = snapshot(vp)
        let m42 = try! #require(contains(snap, ngc: 1976))
        // theta-1 Orionis (the Trapezium) sits inside M42
        let hit = try! #require(
            ChartInteraction.hitTest(at: m42.position, snapshot: snap))
        #expect(hit.catalog == .rngc)
    }

    /// Pan keeps the grabbed sky point under the finger, including at
    /// high declination and across 0h RA.
    @Test func panIsSkyAnchored() {
        // (viewport, drag end). Pole drags use a shorter feasible drag: a
        // north-up chart cannot place a near-polar anchor at an arbitrary
        // bearing, in which case the solver clamps at the pole instead.
        let cases: [(ChartViewport, Point2D)] = [
            (viewport(raHours: 5.6, decDegrees: 0), Point2D(x: 350, y: 500)),
            (viewport(raHours: 0.05, decDegrees: 87.5), Point2D(x: 640, y: 360)),
            (viewport(raHours: 23.95, decDegrees: -30), Point2D(x: 350, y: 500)),
            (
                viewport(raHours: 12, decDegrees: -88, orientation: .downunder),
                Point2D(x: 660, y: 340)
            ),
        ]
        for (vp, target) in cases {
            let start = Point2D(x: 700, y: 300)
            let anchor = ChartProjection.unproject(start, in: vp)
            var moved = vp
            moved.center = ChartInteraction.centerKeeping(
                anchor: anchor, under: target, in: vp)
            let back = ChartProjection.project(anchor, in: moved)
            let dx = back.x - target.x
            let dy = back.y - target.y
            #expect(
                (dx * dx + dy * dy).squareRoot() < 0.5,
                "center \(vp.center): anchor drifted to \(back)")
        }
    }

    /// Near the pole a grab point can be kept under the finger by two
    /// centers, one on each side of the pole. A zero-length drag must
    /// keep the current one rather than jumping across.
    @Test func zeroPanNearPoleKeepsCenter() {
        let vp = viewport(raHours: 2.53, decDegrees: 89.26, scale: 0.04)
        // a grab point past the pole (on the 14h side)
        let start = Point2D(x: 512, y: 100)
        let anchor = ChartProjection.unproject(start, in: vp)
        let center = ChartInteraction.centerKeeping(
            anchor: anchor, under: start, in: vp)
        let separation = ChartProjection.angularSeparation(
            center, vp.center
        ).degrees
        #expect(separation < 1e-6, "jumped to \(center)")
    }

    /// Dragging across the pole clamps there instead of redrawing the
    /// chart rotated 180 degrees: frame to frame, the pole's screen
    /// position never jumps and the chart never turns by more than a few
    /// degrees.
    @Test func panAcrossPoleNeverFlips() {
        let pole = EquatorialCoordinate(
            rightAscension: Radians(0), declination: Radians(.pi / 2))
        let cases: [(ChartViewport, Point2D, Point2D)] = [
            // grab beyond the pole, drag down
            (
                viewport(raHours: 2.53, decDegrees: 89.26, scale: 0.04),
                Point2D(x: 512, y: 100), Point2D(x: 0, y: 600)
            ),
            // centered on the pole, drag down
            (
                viewport(raHours: 14.49, decDegrees: 90, scale: 0.04),
                Point2D(x: 512, y: 100), Point2D(x: 0, y: 300)
            ),
            // grab below center, drag straight through the pole
            (
                viewport(raHours: 2.5, decDegrees: 80, scale: 0.04),
                Point2D(x: 512, y: 384), Point2D(x: 0, y: 600)
            ),
            // the same near the south pole, upside down
            (
                viewport(
                    raHours: 9, decDegrees: -89, scale: 0.04,
                    orientation: .downunder),
                Point2D(x: 512, y: 600), Point2D(x: 40, y: -500)
            ),
        ]
        for (start, grab, drag) in cases {
            var vp = start
            let anchor = ChartProjection.unproject(grab, in: vp)
            let southern = start.center.declination.value < 0
            let trackedPole = southern
                ? EquatorialCoordinate(
                    rightAscension: Radians(0),
                    declination: Radians(-.pi / 2))
                : pole
            var previousPole = ChartProjection.project(trackedPole, in: vp)
            for step in 1...60 {
                let f = Double(step) / 60
                let target = Point2D(
                    x: grab.x + drag.x * f, y: grab.y + drag.y * f)
                vp.center = ChartInteraction.centerKeeping(
                    anchor: anchor, under: target, in: vp)
                let p = ChartProjection.project(trackedPole, in: vp)
                let jump = (
                    (p.x - previousPole.x) * (p.x - previousPole.x)
                        + (p.y - previousPole.y) * (p.y - previousPole.y)
                ).squareRoot()
                // the pole may move with the finger (one step is at most
                // ~10 points) but never leaps across the screen
                #expect(
                    jump < 25,
                    "start \(start.center), step \(step): pole jumped \(jump)")
                previousPole = p
            }
        }
    }

    /// Frame-by-frame drag, as the chart's pan gesture applies it.
    private func drag(
        _ start: ChartViewport, from grab: Point2D, by offset: Point2D,
        steps: Int = 60
    ) -> [ChartViewport] {
        var vp = start
        var previous = grab
        var frames: [ChartViewport] = []
        for step in 1...steps {
            let f = Double(step) / Double(steps)
            let location = Point2D(
                x: grab.x + offset.x * f, y: grab.y + offset.y * f)
            vp = ChartInteraction.panned(vp, from: previous, to: location)
            previous = location
            frames.append(vp)
        }
        return frames
    }

    /// The direction (radians) in which a sky point lies from the screen
    /// center, clockwise from straight down.
    private func bearing(
        of sky: EquatorialCoordinate, in vp: ChartViewport
    ) -> Double {
        let p = ChartProjection.project(sky, in: vp)
        return atan2(
            p.x - vp.sizeInPoints.width / 2, p.y - vp.sizeInPoints.height / 2)
    }

    /// Dragging a pole to the center and on past it stops there: the
    /// center stays on the pole and the chart does not turn, wherever the
    /// finger is relative to the pole.
    @Test func dragPastPoleStopsWithoutSpinning() {
        let sky = EquatorialCoordinate(
            rightAscension: Radians(hours: 6), declination: Radians(degrees: -75))
        let cases: [(ChartViewport, Point2D, Point2D)] = [
            // south pole below center: drag it up through the center
            (
                viewport(raHours: 3, decDegrees: -80, scale: 0.04),
                Point2D(x: 700, y: 640), Point2D(x: 0, y: -500)
            ),
            // the same, finger well off to the side and drifting
            (
                viewport(raHours: 3, decDegrees: -80, scale: 0.04),
                Point2D(x: 900, y: 700), Point2D(x: -12, y: -600)
            ),
            // passing just beside the pole rather than through it
            (
                viewport(raHours: 3, decDegrees: -80, scale: 0.04),
                Point2D(x: 515, y: 640), Point2D(x: 0, y: -500)
            ),
            // north pole above center, upside down
            (
                viewport(
                    raHours: 15, decDegrees: 80, scale: 0.04,
                    orientation: .downunder),
                Point2D(x: 300, y: 640), Point2D(x: 0, y: -500)
            ),
        ]
        for (start, grab, offset) in cases {
            let frames = drag(start, from: grab, by: offset)
            let reference = EquatorialCoordinate(
                rightAscension: sky.rightAscension,
                declination: Radians(
                    start.center.declination.value < 0
                        ? sky.declination.value : -sky.declination.value))
            let firstAtPole = try! #require(
                frames.firstIndex {
                    abs($0.center.declination.degrees) > 90 - 1e-6
                }, "never reached the pole from \(start.center)")
            #expect(firstAtPole < 45)
            let settled = bearing(of: reference, in: frames[firstAtPole])
            for vp in frames[firstAtPole...] {
                #expect(abs(vp.center.declination.degrees) > 90 - 1e-6)
                var turned = abs(bearing(of: reference, in: vp) - settled)
                turned = min(turned, 2 * .pi - turned)
                // only the horizontal drift may turn the chart, by about
                // 12 points around a 350-point radius
                #expect(
                    turned < 3 * Double.pi / 180,
                    "from \(start.center): turned \(turned) rad at the pole")
            }
        }
    }

    /// At a pole a horizontal drag turns the chart about it: the sky
    /// below the pole moves with a finger below it, and against a finger
    /// above it, in either orientation.
    @Test func horizontalDragAtPoleTurnsChart() {
        for (decDegrees, orientation) in [
            (-90.0, ChartOrientation.normal), (90, .normal),
            (-90, .downunder), (90, .downunder),
        ] {
            let vp = viewport(
                raHours: 4, decDegrees: decDegrees, scale: 0.04,
                orientation: orientation)
            let below = Point2D(x: 512, y: 684)
            let above = Point2D(x: 512, y: 84)
            let skyBelow = ChartProjection.unproject(below, in: vp)
            for (grab, sign) in [(below, 1.0), (above, -1.0)] {
                let moved = try! #require(
                    drag(vp, from: grab, by: Point2D(x: 60, y: 0)).last)
                let p = ChartProjection.project(skyBelow, in: moved)
                #expect(
                    abs(moved.center.declination.degrees) > 90 - 1e-6)
                // about 60 points along a 300-point radius
                #expect(
                    abs((p.x - below.x) - 60 * sign) < 6,
                    "dec \(decDegrees) \(orientation), grab \(grab): \(p)")
            }
        }
    }

    /// From a pole, a drag away from it pans normally again.
    @Test func dragAwayFromPoleLeavesIt() {
        // the south pole sits below center on a north-up chart, so
        // dragging down pulls it down and away
        let vp = viewport(raHours: 4, decDegrees: -90, scale: 0.04)
        let grab = Point2D(x: 512, y: 300)
        let moved = try! #require(
            drag(vp, from: grab, by: Point2D(x: 0, y: 200)).last)
        let anchor = ChartProjection.unproject(grab, in: vp)
        let p = ChartProjection.project(anchor, in: moved)
        #expect(abs(moved.center.declination.degrees + 82) < 0.2)
        #expect(abs(p.y - 500) < 1 && abs(p.x - 512) < 1, "\(p)")
    }

    /// Pinch stays anchored to its centroid within one logical point.
    @Test func zoomIsAnchoredAtCentroid() {
        let vp = viewport(raHours: 5.6, decDegrees: 30)
        let centroid = Point2D(x: 650, y: 250)
        let sky = ChartProjection.unproject(centroid, in: vp)
        for factor in [0.5, 0.8, 1.25, 2.0] {
            let zoomed = ChartInteraction.zoomedViewport(
                vp, scaleFactor: factor, anchor: centroid)
            let p = ChartProjection.project(sky, in: zoomed)
            let dx = p.x - centroid.x
            let dy = p.y - centroid.y
            #expect(
                (dx * dx + dy * dy).squareRoot() < 1.0,
                "factor \(factor) drifted to \(p)")
        }
    }

    @Test func regionZoomCentersAndScales() {
        let vp = viewport(raHours: 5.6, decDegrees: 0)
        let zoomed = ChartInteraction.regionZoomedViewport(
            vp, regionOrigin: Point2D(x: 400, y: 300),
            regionSize: Size2D(width: 200, height: 150))
        #expect(zoomed.degreesPerPoint < vp.degreesPerPoint)
        // region center sky position lands at the viewport center
        let regionCenterSky = ChartProjection.unproject(
            Point2D(x: 500, y: 375), in: vp)
        let p = ChartProjection.project(regionCenterSky, in: zoomed)
        #expect(abs(p.x - 512) < 1 && abs(p.y - 384) < 1)
    }

    /// Snapshot construction must stay within the performance budget for
    /// a typical settled view (p95 under 100ms).
    @Test func snapshotBuildIsFastEnough() {
        let builder = ChartSceneBuilder(store: store)
        var settings = ChartSettings()
        settings.showBoundaries = true
        settings.showOutlines = true
        // warm up
        _ = builder.buildSnapshot(
            viewport: viewport(raHours: 5.6, decDegrees: 0),
            settings: settings, labels: [], selection: nil, generation: 0)
        var worst: Duration = .zero
        for hours in [0.0, 5.6, 12.0, 18.0] {
            let vp = viewport(raHours: hours, decDegrees: 20, scale: 0.1)
            let start = ContinuousClock.now
            _ = builder.buildSnapshot(
                viewport: vp, settings: settings, labels: [], selection: nil,
                generation: 0)
            worst = max(worst, ContinuousClock.now - start)
        }
        #expect(worst < .milliseconds(150), "worst build took \(worst)")
    }

    @Test func labelsProjectWithAnchors() {
        let vp = viewport(raHours: 5.6, decDegrees: 0)
        let m42ID = snapshot(vp).objects.first {
            if case .rngc(1976, nil, _)? = store.object($0.objectID)?.identity {
                return true
            }
            return false
        }?.objectID
        let labels = [
            ChartLabel(anchor: .object(try! #require(m42ID)), text: "M 42"),
            ChartLabel(
                anchor: .sky(
                    raRadians: Radians(hours: 5.6).value,
                    decRadians: 0), text: "note"),
        ]
        let snap = ChartSceneBuilder(store: store).buildSnapshot(
            viewport: vp, settings: ChartSettings(), labels: labels,
            selection: nil, generation: 2)
        #expect(snap.labels.count == 2)
    }
}
