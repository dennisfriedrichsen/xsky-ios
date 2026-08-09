import SwiftUI
import XSkyCore

/// Sidebar sections: Catalogs, Layers, Magnitudes, Labels, Display.
struct SidebarView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Binding var showImporter: Bool

    var body: some View {
        List {
            catalogsSection
            layersSection
            magnitudesSection
            labelsSection
            displaySection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.05))
        .accessibilityIdentifier("sidebar")
    }

    // MARK: catalogs

    private var catalogsSection: some View {
        Section("Catalogs") {
            if let store = workspace.store {
                catalogRow(.ybs, store: store)
                catalogRow(.rngc, store: store)
                catalogRow(.qso, store: store)
                ForEach(store.userCatalogIDs, id: \.rawValue) { id in
                    userCatalogRow(id, store: store)
                }
            } else {
                Text("Loading…").foregroundStyle(.secondary)
            }
            Button {
                showImporter = true
            } label: {
                Label("Import User Catalog…", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("sidebar.importUserCatalog")
        }
    }

    private func catalogRow(_ id: CatalogID, store: CatalogStore) -> some View {
        let catalog = store.catalogs[id]
        return Toggle(isOn: catalogBinding(id)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(catalog?.shortName ?? id.rawValue)
                Text("\(catalog?.objects.count ?? 0) objects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("sidebar.catalog.\(id.rawValue)")
    }

    private func userCatalogRow(_ id: CatalogID, store: CatalogStore) -> some View {
        let catalog = store.catalogs[id]
        return HStack {
            Toggle(isOn: catalogBinding(id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(catalog?.displayName ?? "User Catalog")
                        .lineLimit(1)
                    Text("\(catalog?.objects.count ?? 0) objects · imported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button(role: .destructive) {
                Task { await workspace.removeUserCatalog(id: id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove imported catalog")
            .accessibilityIdentifier("sidebar.removeUserCatalog")
        }
    }

    private func catalogBinding(_ id: CatalogID) -> Binding<Bool> {
        Binding(
            get: { workspace.settings.isVisible(catalog: id) },
            set: { visible in
                workspace.updateSettings(
                    { $0.setVisible(visible, catalog: id) },
                    undoLabel: visible ? "Show Catalog" : "Hide Catalog")
            })
    }

    // MARK: layers

    private var layersSection: some View {
        Section("Layers") {
            settingToggle("Coordinate Grid", \.showGrid, id: "grid")
            settingToggle(
                "Constellation Boundaries", \.showBoundaries, id: "boundaries")
            settingToggle(
                "Constellation Outlines", \.showOutlines, id: "outlines")
            settingToggle("Object Labels", \.showObjectLabels, id: "objectLabels")
            settingToggle("Star Labels", \.showStarLabels, id: "starLabels")
            settingToggle(
                "Constellation Labels", \.showConstellationLabels,
                id: "constellationLabels")
                .disabled(!workspace.hasConstellationLabels)
        }
    }

    private func settingToggle(
        _ title: String, _ keyPath: WritableKeyPath<ChartSettings, Bool>,
        id: String
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { workspace.settings[keyPath: keyPath] },
                set: { value in
                    workspace.updateSettings(
                        { $0[keyPath: keyPath] = value }, undoLabel: title)
                }))
            .accessibilityIdentifier("sidebar.layer.\(id)")
    }

    // MARK: magnitudes

    private var magnitudesSection: some View {
        Section("Magnitudes") {
            magnitudeSlider(
                "Stellar limit", \.stellarLimitingMagnitude, range: -1.5...8.0,
                id: "stellarLimit")
            magnitudeSlider(
                "Non-stellar limit", \.nonstellarLimitingMagnitude,
                range: 0...16.0, id: "nonstellarLimit")
            magnitudeSlider(
                "Max star size at mag", \.maximumSizeMagnitude,
                range: -1.5...4.0, id: "maxSizeMagnitude")
            settingToggle(
                "Unknown-Magnitude Objects", \.showUnknownMagnitude,
                id: "unknownMagnitude")
            settingToggle(
                "Nonexistent / Unverified", \.showNonexistentObjects,
                id: "nonexistent")
        }
    }

    private func magnitudeSlider(
        _ title: String, _ keyPath: WritableKeyPath<ChartSettings, Double>,
        range: ClosedRange<Double>, id: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f", workspace.settings[keyPath: keyPath]))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { workspace.settings[keyPath: keyPath] },
                    set: { value in
                        workspace.updateSettings(
                            { $0[keyPath: keyPath] = (value * 10).rounded() / 10 },
                            undoLabel: title)
                    }),
                in: range)
                .accessibilityLabel(title)
                .accessibilityValue(
                    String(format: "%.1f", workspace.settings[keyPath: keyPath]))
                .accessibilityIdentifier("sidebar.magnitude.\(id)")
        }
    }

    // MARK: labels

    private var labelsSection: some View {
        Section("Labels") {
            Button("Generate Object Labels") {
                workspace.generateObjectLabels()
            }
            .accessibilityIdentifier("sidebar.generateLabels")
            Button("Generate Constellation Labels") {
                workspace.generateConstellationLabels()
            }
            .accessibilityIdentifier("sidebar.generateConstellationLabels")
            Button("Clear All Labels", role: .destructive) {
                // immediate undo is available from the toolbar
                workspace.clearLabels()
            }
            .disabled(workspace.labels.isEmpty)
            .accessibilityIdentifier("sidebar.clearLabels")
            Text("\(workspace.labels.count) labels")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: display

    private var displaySection: some View {
        Section("Display") {
            displayToggle("Spectral Colors", \.colorMode, id: "colorMode")
            displayToggle("Night Mode", \.nightMode, id: "nightMode")
            Toggle(
                "Downunder Orientation",
                isOn: Binding(
                    get: { workspace.viewport.orientation == .downunder },
                    set: { down in
                        var vp = workspace.viewport
                        vp.orientation = down ? .downunder : .normal
                        workspace.commitViewport(vp, undoLabel: "Orientation")
                    }))
                .accessibilityIdentifier("sidebar.display.downunder")
            VStack(alignment: .leading, spacing: 2) {
                Text("Chart Label Size")
                Slider(
                    value: Binding(
                        get: { workspace.display.chartLabelScale },
                        set: { workspace.display.chartLabelScale = $0 }),
                    in: 0.7...2.0)
                    .accessibilityLabel("Chart label size")
                    .accessibilityIdentifier("sidebar.display.labelScale")
            }
            Button("Reset to Default View") {
                workspace.resetToDefaultView()
            }
            .accessibilityIdentifier("sidebar.resetView")
        }
    }

    private func displayToggle(
        _ title: String, _ keyPath: WritableKeyPath<DisplaySettings, Bool>,
        id: String
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { workspace.display[keyPath: keyPath] },
                set: { workspace.display[keyPath: keyPath] = $0 }))
            .accessibilityIdentifier("sidebar.display.\(id)")
    }
}
