import Foundation
import Observation
import SwiftUI
import XSkyCore
import os

/// The single main-actor observable model for user-visible state: chart
/// viewport, settings, selection, labels, undo, and scene generation.
/// Catalog data lives in the CatalogRepository actor; scene builds run
/// off the main actor with stale-result protection.
@MainActor
@Observable
final class WorkspaceModel {
    // MARK: chart state
    var viewport = ChartViewport.initialViewport(
        size: Size2D(width: 1024, height: 768))
    /// Transient gesture preview; committed once at gesture end.
    var gestureViewport: ChartViewport?
    var settings = ChartSettings() {
        didSet { scheduleRebuild(); schedulePersist() }
    }
    var display = DisplaySettings() {
        didSet { schedulePersist() }
    }
    var labels: [ChartLabel] = [] {
        didSet { scheduleRebuild(); schedulePersist() }
    }
    var hasConstellationLabels: Bool {
        labels.contains {
            if case .constellation = $0.anchor { return true }
            return false
        }
    }
    var selection: CatalogObjectID? {
        didSet {
            selectedDetails = selection.flatMap { id in
                store.flatMap { ObjectDetails.build(for: $0.object(id) ?? nil, store: $0) }
            }
            if selection != nil { inspectorVisible = true }
            scheduleRebuild()
        }
    }
    var selectedDetails: ObjectDetails?

    // MARK: data
    private(set) var store: CatalogStore?
    private(set) var snapshot: RenderSnapshot?
    var loadState: LoadState = .loading

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    // MARK: UI state
    var sidebarVisible = false { didSet { schedulePersist() } }
    var inspectorVisible = false { didSet { schedulePersist() } }
    var regionZoomArmed = false
    var hoverReadout: String?
    var searchText = ""
    var searchResults: [SearchResult] = []
    var pendingCatalogEnable: (result: SearchResult, catalog: CatalogID)?
    var importDiagnostics: String?

    let undoManager = UndoManager()

    private var repository: CatalogRepository?
    private var generation: UInt64 = 0
    private var buildTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.dennisfriedrichsen.xsky", category: "workspace")

    init() {
        restorePersistedState()
    }

    // MARK: startup

    func start() async {
        guard repository == nil else { return }
        undoManager.levelsOfUndo = 100

        let repo = CatalogRepository(
            locator: BundleResourceLocator(),
            userCatalogDirectory: try? Self.userCatalogDirectory())
        repository = repo
        do {
            let store = try await repo.loadAll()
            self.store = store
            loadState = .ready
            scheduleRebuild()
        } catch {
            loadState = .failed(String(describing: error))
            log.error("catalog load failed: \(String(describing: error))")
        }
    }

    static func userCatalogDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return base.appendingPathComponent("XSky/UserCatalogs", isDirectory: true)
    }

    // MARK: scene generation

    /// The viewport being displayed right now (gesture preview wins).
    var activeViewport: ChartViewport { gestureViewport ?? viewport }

    func updateChartSize(_ size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }
        let newSize = Size2D(width: size.width, height: size.height)
        guard newSize != viewport.sizeInPoints else { return }
        viewport.sizeInPoints = newSize
        scheduleRebuild()
    }

    func scheduleRebuild() {
        rebuild(viewport: viewport)
    }

    /// Exact rebuild for the in-flight gesture viewport; stale results
    /// are discarded by generation, so only the newest snapshot lands.
    func rebuildForGesturePreview() {
        rebuild(viewport: activeViewport)
    }

    private func rebuild(viewport vp: ChartViewport) {
        guard let store else { return }
        generation &+= 1
        let g = generation
        let builder = ChartSceneBuilder(store: store)
        let settings = self.settings
        let labels = self.labels
        let selection = self.selection
        buildTask?.cancel()
        buildTask = Task.detached(priority: .userInitiated) {
            if Task.isCancelled { return }
            let snap = builder.buildSnapshot(
                viewport: vp, settings: settings, labels: labels,
                selection: selection, generation: g)
            await MainActor.run { [weak self] in
                guard let self, snap.generation == self.generation else {
                    return
                }
                self.snapshot = snap
            }
        }
    }

    // MARK: viewport changes with undo

    func commitViewport(_ new: ChartViewport, undoLabel: String) {
        let old = viewport
        guard old != new else { return }
        viewport = new
        gestureViewport = nil
        registerViewportUndo(old, label: undoLabel)
        scheduleRebuild()
        schedulePersist()
    }

    private func registerViewportUndo(_ old: ChartViewport, label: String) {
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.commitViewport(old, undoLabel: label)
            }
        }
        undoManager.setActionName(label)
    }

    func center(on coordinate: EquatorialCoordinate, undoLabel: String = "Center") {
        var vp = viewport
        vp.center = coordinate
        commitViewport(vp, undoLabel: undoLabel)
    }

    func zoomStep(in zoomIn: Bool, anchor: Point2D? = nil) {
        let factor =
            zoomIn
            ? ChartInteraction.zoomInStepFactor
            : ChartInteraction.zoomOutStepFactor
        let anchorPoint =
            anchor
            ?? Point2D(
                x: viewport.sizeInPoints.width / 2,
                y: viewport.sizeInPoints.height / 2)
        commitViewport(
            ChartInteraction.zoomedViewport(
                viewport, scaleFactor: factor, anchor: anchorPoint),
            undoLabel: zoomIn ? "Zoom In" : "Zoom Out")
    }

    func pan(byPoints dx: Double, _ dy: Double) {
        let center = Point2D(
            x: viewport.sizeInPoints.width / 2,
            y: viewport.sizeInPoints.height / 2)
        let anchor = ChartProjection.unproject(center, in: viewport)
        var vp = viewport
        vp.center = ChartInteraction.centerKeeping(
            anchor: anchor,
            under: Point2D(x: center.x + dx, y: center.y + dy), in: viewport)
        commitViewport(vp, undoLabel: "Pan")
    }

    func resetToDefaultView() {
        commitViewport(
            ChartViewport.initialViewport(size: viewport.sizeInPoints),
            undoLabel: "Reset View")
    }

    // MARK: settings with undo

    func updateSettings(
        _ transform: (inout ChartSettings) -> Void, undoLabel: String
    ) {
        let old = settings
        var new = settings
        transform(&new)
        guard new != old else { return }
        settings = new
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.updateSettings({ $0 = old }, undoLabel: undoLabel)
            }
        }
        undoManager.setActionName(undoLabel)
    }

    // MARK: selection

    func selectObject(at point: Point2D) {
        guard let snapshot else { return }
        selection = ChartInteraction.hitTest(at: point, snapshot: snapshot)
    }

    func constellationName(at point: Point2D) -> String? {
        let coordinate = ChartProjection.unproject(point, in: activeViewport)
        return ConstellationIdentifier().constellation(of: coordinate)?.name
    }

    // MARK: labels with undo

    func performLabelChange(
        _ new: [ChartLabel], undoLabel: String
    ) {
        let old = labels
        guard new != old else { return }
        labels = new
        undoManager.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.performLabelChange(old, undoLabel: undoLabel)
            }
        }
        undoManager.setActionName(undoLabel)
    }

    func addLabel(forObject id: CatalogObjectID) {
        guard let store, let object = store.object(id),
            let catalog = store.catalog(id.catalog)
        else { return }
        guard !labels.contains(where: { $0.anchor == .object(id) }) else {
            return
        }
        let label = ChartLabel(
            anchor: .object(id),
            text: ObjectLabels.chartLabel(for: object, in: catalog))
        performLabelChange(labels + [label], undoLabel: "Add Label")
    }

    func removeLabel(forObject id: CatalogObjectID) {
        performLabelChange(
            labels.filter { $0.anchor != .object(id) },
            undoLabel: "Remove Label")
    }

    func hasLabel(forObject id: CatalogObjectID) -> Bool {
        labels.contains { $0.anchor == .object(id) }
    }

    /// Generate labels for eligible visible non-stellar objects and
    /// Bayer-designated stars (legacy auto_generate_object_ids).
    func generateObjectLabels() {
        guard let store, let snapshot else { return }
        var new = labels
        func append(_ id: CatalogObjectID) {
            guard let object = store.object(id),
                let catalog = store.catalog(id.catalog),
                !new.contains(where: { $0.anchor == .object(id) })
            else { return }
            if object.isStellar {
                guard case .ybs(_, .some, _, _, _) = object.identity else {
                    return
                }
            }
            new.append(
                ChartLabel(
                    anchor: .object(id),
                    text: ObjectLabels.chartLabel(for: object, in: catalog)))
        }
        for rendered in snapshot.objects { append(rendered.objectID) }
        for star in snapshot.stars { append(star.objectID) }
        performLabelChange(new, undoLabel: "Generate Labels")
    }

    func generateConstellationLabels() {
        guard let store else { return }
        var new = labels
        for (i, entry) in ConstellationTable.entries.enumerated()
        where i < store.constellationCenters.count {
            guard !new.contains(where: { $0.anchor == .constellation(i) })
            else { continue }
            new.append(
                ChartLabel(
                    anchor: .constellation(i), text: entry.name,
                    offsetX: 0, offsetY: 0))
        }
        performLabelChange(new, undoLabel: "Constellation Labels")
    }

    func clearLabels() {
        performLabelChange([], undoLabel: "Clear Labels")
    }

    func moveLabel(id: ChartLabelID, offsetX: Double, offsetY: Double) {
        var new = labels
        guard let i = new.firstIndex(where: { $0.id == id }) else { return }
        new[i].offsetX = offsetX
        new[i].offsetY = offsetY
        performLabelChange(new, undoLabel: "Move Label")
    }

    // MARK: search

    func updateSearchResults() {
        guard let store else {
            searchResults = []
            return
        }
        searchResults = store.searchEngine.suggestions(for: searchText)
    }

    /// Centering a hidden-catalog result asks before enabling the catalog
    /// rather than silently changing layer state.
    func activate(result: SearchResult) {
        if let catalogID = result.catalogID,
            !settings.isVisible(catalog: catalogID)
        {
            pendingCatalogEnable = (result, catalogID)
            return
        }
        performActivation(result)
    }

    func performActivation(_ result: SearchResult) {
        center(
            on: EquatorialCoordinate(
                rightAscension: Radians(result.raRadians),
                declination: Radians(result.decRadians)),
            undoLabel: "Go To Search Result")
        if case .object(let id) = result.target {
            selection = id
        }
        searchText = ""
        searchResults = []
    }

    // MARK: user catalog import

    func importUserCatalog(from url: URL) async {
        guard let repository else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let (store, _, diagnostics) = try await repository.importUserCatalog(
                data: data, suggestedName: url.lastPathComponent)
            self.store = store
            if !diagnostics.skipped.isEmpty {
                importDiagnostics = diagnostics.skipped
                    .map { "\($0.value)× \($0.key)" }
                    .joined(separator: "\n")
            }
            scheduleRebuild()
        } catch {
            importDiagnostics = "Import failed: \(error.localizedDescription)"
        }
    }

    func removeUserCatalog(id: CatalogID) async {
        guard let repository else { return }
        if let store = await repository.removeUserCatalog(id: id) {
            self.store = store
            if selection?.catalog == id { selection = nil }
            scheduleRebuild()
        }
    }

    // MARK: persistence

    private func restorePersistedState() {
        guard let url = try? WorkspacePersistence.defaultFileURL(),
            let saved = WorkspacePersistence.load(from: url)
        else { return }
        viewport = ChartViewport(
            center: EquatorialCoordinate(
                rightAscension: Radians(saved.centerRARadians),
                declination: Radians(saved.centerDecRadians)),
            degreesPerPoint: saved.degreesPerPoint,
            sizeInPoints: viewport.sizeInPoints,
            orientation: saved.orientation)
        settings = saved.settings
        display = saved.displaySettings
        labels = saved.labels
        sidebarVisible = saved.sidebarVisible
        inspectorVisible = saved.inspectorVisible
    }

    func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    func persistNow() {
        guard let url = try? WorkspacePersistence.defaultFileURL() else {
            return
        }
        let saved = SavedWorkspaceV1(
            centerRARadians: viewport.center.rightAscension.value,
            centerDecRadians: viewport.center.declination.value,
            degreesPerPoint: viewport.degreesPerPoint,
            orientation: viewport.orientation,
            settings: settings,
            displaySettings: display,
            labels: labels,
            sidebarVisible: sidebarVisible,
            inspectorVisible: inspectorVisible)
        do {
            try WorkspacePersistence.save(saved, to: url)
        } catch {
            log.error("persist failed: \(String(describing: error))")
        }
    }

    // MARK: readouts

    var centerReadout: String {
        let ra = SexagesimalRA(radians: activeViewport.center.rightAscension)
        let dec = SexagesimalDec(radians: activeViewport.center.declination)
        return "\(ra.displayString)  \(dec.displayString)"
    }

    var fieldReadout: String {
        let width =
            activeViewport.sizeInPoints.width * activeViewport.degreesPerPoint
        let height =
            activeViewport.sizeInPoints.height * activeViewport.degreesPerPoint
        return String(format: "%.1f° × %.1f°", width, height)
    }
}

extension CatalogStore {
    func object(_ id: CatalogObjectID?) -> CatalogObject? {
        guard let id else { return nil }
        return object(id)
    }
}

extension ObjectDetails {
    static func build(
        for object: CatalogObject?, store: CatalogStore
    ) -> ObjectDetails? {
        guard let object else { return nil }
        return build(for: object, store: store)
    }
}
