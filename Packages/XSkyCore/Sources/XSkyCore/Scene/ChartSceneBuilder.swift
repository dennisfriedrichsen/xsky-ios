import Foundation

/// Builds immutable render snapshots from the catalog store, viewport,
/// and settings. Pure and synchronous; callers run it off the main actor
/// and use the generation counter to discard stale results.
public struct ChartSceneBuilder: Sendable {
    public let store: CatalogStore

    public init(store: CatalogStore) {
        self.store = store
    }

    public func buildSnapshot(
        viewport: ChartViewport,
        settings: ChartSettings,
        labels: [ChartLabel],
        selection: CatalogObjectID?,
        generation: UInt64
    ) -> RenderSnapshot {
        let tester = VisibilityTester(viewport: viewport)

        var stars: [RenderedStar] = []
        var objects: [RenderedObject] = []

        for (catalogID, catalog) in store.catalogs {
            guard settings.isVisible(catalog: catalogID),
                let index = store.spatialIndexes[catalogID]
            else { continue }

            for i in index.candidates(in: tester.bounds) {
                let object = catalog.objects[i]
                guard settings.passesFilters(object) else { continue }
                guard
                    let p = tester.visiblePosition(
                        rightAscension: object.raRadians,
                        declination: object.decRadians)
                else { continue }

                if object.isStellar {
                    stars.append(
                        RenderedStar(
                            position: p,
                            diameter: StarSizing.diameter(
                                magnitude: object.magnitude ?? 0,
                                maxDiameter: settings.maximumStarDiameter,
                                maxSizeMagnitude: settings.maximumSizeMagnitude),
                            color: object.spectralClass ?? .neutral,
                            objectID: object.id))
                } else {
                    objects.append(
                        RenderedObject(
                            position: p,
                            symbol: ChartSymbol(kind: object.kind),
                            size: settings.objectSymbolSize,
                            objectID: object.id))
                }
            }
        }

        // draw faint stars first so bright stars stay on top
        stars.sort { ($0.diameter, $0.position.x) < ($1.diameter, $1.position.x) }

        var snapshot = RenderSnapshot(
            viewport: viewport,
            stars: stars,
            objects: objects,
            generation: generation)

        if settings.showGrid {
            snapshot.gridPaths = GridPathBuilder.gridPaths(
                viewport: viewport, bounds: tester.bounds)
        }
        if settings.showBoundaries {
            snapshot.boundaryPaths = projectPaths(
                store.boundaries, tester: tester)
        }
        if settings.showOutlines {
            snapshot.outlinePaths = projectPaths(store.outlines, tester: tester)
        }

        snapshot.labels = buildLabels(
            labels, viewport: viewport, tester: tester, settings: settings)

        if let selection, let object = store.object(selection),
            let p = tester.visiblePosition(
                rightAscension: object.raRadians,
                declination: object.decRadians)
        {
            snapshot.selection = RenderedSelection(
                position: p, objectID: selection)
        }

        return snapshot
    }

    // MARK: boundaries and outlines

    /// Projects celestial polylines, keeping segments with a visible
    /// endpoint and segments that cross the viewport with both endpoints
    /// outside (an improvement over the legacy endpoint-only test).
    private func projectPaths(
        _ paths: [CelestialPath], tester: VisibilityTester
    ) -> [Polyline] {
        let viewport = tester.viewport
        let width = viewport.sizeInPoints.width
        let height = viewport.sizeInPoints.height
        // reject wrap-around segments: anything spanning more than half
        // the viewport diagonal in one hop is a projection artifact
        let maxHop = 2 * (width * width + height * height).squareRoot()

        var result: [Polyline] = []
        var current: [Point2D] = []

        func flush() {
            if current.count >= 2 { result.append(Polyline(points: current)) }
            current = []
        }

        for path in paths {
            guard path.points.count >= 2 else { continue }
            var pts = path.points
            if path.closed, let first = pts.first {
                pts.append(first)
            }

            var previous = ChartProjection.project(
                rightAscension: pts[0].raRadians,
                declination: pts[0].decRadians, in: viewport)
            var previousVisible = contains(previous, width, height)

            for i in 1..<pts.count {
                let point = ChartProjection.project(
                    rightAscension: pts[i].raRadians,
                    declination: pts[i].decRadians, in: viewport)
                let visible = contains(point, width, height)

                let crosses =
                    segmentIntersectsViewport(
                        previous, point, width: width, height: height)
                    && hop(previous, point) < maxHop

                if previousVisible || visible || crosses {
                    if current.isEmpty { current.append(previous) }
                    current.append(point)
                } else {
                    flush()
                }
                previous = point
                previousVisible = visible
            }
            flush()
        }
        return result
    }

    private func contains(_ p: Point2D, _ w: Double, _ h: Double) -> Bool {
        p.x >= 0 && p.x < w && p.y >= 0 && p.y < h
    }

    private func hop(_ a: Point2D, _ b: Point2D) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func segmentIntersectsViewport(
        _ a: Point2D, _ b: Point2D, width: Double, height: Double
    ) -> Bool {
        // AABB rejection is cheap and adequate as a crossing candidate;
        // false positives merely add an off-screen line segment
        let minX = min(a.x, b.x)
        let maxX = max(a.x, b.x)
        let minY = min(a.y, b.y)
        let maxY = max(a.y, b.y)
        return maxX >= 0 && minX < width && maxY >= 0 && minY < height
    }

    // MARK: labels

    private func buildLabels(
        _ labels: [ChartLabel], viewport: ChartViewport,
        tester: VisibilityTester, settings: ChartSettings
    ) -> [RenderedLabel] {
        var rendered: [RenderedLabel] = []
        for label in labels where !label.isHidden {
            let kind: RenderedLabel.Kind
            let ra: Double
            let dec: Double
            switch label.anchor {
            case .object(let id):
                guard let object = store.object(id) else { continue }
                kind = object.isStellar ? .object : .object
                if object.isStellar, !settings.showStarLabels { continue }
                if !object.isStellar, !settings.showObjectLabels { continue }
                ra = object.raRadians
                dec = object.decRadians
            case .constellation(let index):
                guard settings.showConstellationLabels,
                    index >= 0, index < store.constellationCenters.count
                else { continue }
                kind = .constellation
                ra = store.constellationCenters[index].raRadians
                dec = store.constellationCenters[index].decRadians
            case .sky(let r, let d):
                kind = .user
                ra = r
                dec = d
            }
            guard
                let p = tester.visiblePosition(
                    rightAscension: ra, declination: dec)
            else { continue }
            rendered.append(
                RenderedLabel(
                    anchor: p,
                    offset: Point2D(x: label.offsetX, y: label.offsetY),
                    text: label.text,
                    kind: kind,
                    labelID: label.id))
        }
        return rendered
    }
}

/// Ported grid construction (grid.c): "nice interval" line spacing with
/// polyline sampling instead of dot plotting.
enum GridPathBuilder {
    static let fullCircleRA = 24 * 60 * 60 * 1000

    static func gridPaths(
        viewport: ChartViewport, bounds: ViewportBounds
    ) -> [Polyline] {
        var paths: [Polyline] = []

        let startRA = GridIntervals.raThousandths(fromRadians: bounds.rightRA)
        let endRA = GridIntervals.raThousandths(fromRadians: bounds.leftRA)
        let startDec = GridIntervals.decHundredths(fromRadians: bounds.bottomDec)
        let endDec = GridIntervals.decHundredths(fromRadians: bounds.topDec)

        let raLineInterval = GridIntervals.raLineInterval(for: viewport)
        let decLineInterval = GridIntervals.decLineInterval(for: viewport)

        // RA lines are sampled at a step that divides the declination
        // interval (legacy dot-interval rule)
        let raSampleStep = GridIntervals.samplingStep(dividing: decLineInterval)

        var lineRA = cDiv(startRA + raLineInterval, raLineInterval) * raLineInterval
        let lineEndRA = cDiv(endRA, raLineInterval) * raLineInterval

        var sampleStartDec: Int
        if startDec < 0 {
            sampleStartDec = cDiv(startDec - raSampleStep + 1, raSampleStep) * raSampleStep
        } else {
            sampleStartDec = cDiv(startDec, raSampleStep) * raSampleStep
        }

        var stopOnGreaterEqual = lineRA <= lineEndRA
        var raGuard = 0
        while raGuard < 4000 {
            raGuard += 1
            paths.append(
                raLine(
                    ra: lineRA, startDec: sampleStartDec, endDec: endDec,
                    step: raSampleStep, viewport: viewport))
            if lineRA >= lineEndRA, stopOnGreaterEqual { break }
            lineRA += raLineInterval
            if lineRA > fullCircleRA {
                lineRA -= fullCircleRA
                stopOnGreaterEqual = true
            }
        }

        // declination lines sample at a step dividing the RA interval
        let decSampleStep = GridIntervals.samplingStep(dividing: raLineInterval)

        var lineDec: Int
        if startDec < 0 {
            lineDec = cDiv(startDec, decLineInterval) * decLineInterval
        } else {
            lineDec = cDiv(startDec + decLineInterval, decLineInterval) * decLineInterval
        }
        let lineEndDec: Int
        if endDec < 0 {
            lineEndDec = cDiv(endDec - decLineInterval, decLineInterval) * decLineInterval
        } else {
            lineEndDec = cDiv(endDec, decLineInterval) * decLineInterval
        }

        while lineDec <= lineEndDec {
            if abs(lineDec) != 90 * 60 * 60 * 100 {
                paths.append(
                    decLine(
                        dec: lineDec, startRA: cDiv(startRA, decSampleStep) * decSampleStep,
                        endRA: endRA, step: decSampleStep, viewport: viewport))
            }
            lineDec += decLineInterval
        }

        return paths.filter { $0.points.count >= 2 }
    }

    /// C integer division truncates toward zero; Swift matches, but keep
    /// the intent explicit at call sites.
    private static func cDiv(_ a: Int, _ b: Int) -> Int { a / b }

    private static func raLine(
        ra: Int, startDec: Int, endDec: Int, step: Int,
        viewport: ChartViewport
    ) -> Polyline {
        var points: [Point2D] = []
        let raRad = GridIntervals.raRadians(fromThousandths: ra)
        var dec = startDec
        while dec <= endDec {
            points.append(
                ChartProjection.project(
                    rightAscension: raRad,
                    declination: GridIntervals.decRadians(fromHundredths: dec),
                    in: viewport))
            dec += step
        }
        return Polyline(points: points)
    }

    private static func decLine(
        dec: Int, startRA: Int, endRA: Int, step: Int,
        viewport: ChartViewport
    ) -> Polyline {
        var points: [Point2D] = []
        let decRad = GridIntervals.decRadians(fromHundredths: dec)
        var ra = startRA
        var stopOnGreaterEqual = ra <= endRA
        var guardCount = 0
        while guardCount < 100_000 {
            guardCount += 1
            points.append(
                ChartProjection.project(
                    rightAscension: GridIntervals.raRadians(fromThousandths: ra),
                    declination: decRad,
                    in: viewport))
            ra += step
            if ra > endRA, stopOnGreaterEqual { break }
            if ra > fullCircleRA {
                ra -= fullCircleRA
                stopOnGreaterEqual = true
            }
        }
        return Polyline(points: points)
    }
}
