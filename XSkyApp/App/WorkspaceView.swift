import SwiftUI
import XSkyCore

/// Root workspace: toolbar, collapsible sidebar, chart, optional
/// inspector, and the chart HUD. Custom composition (not
/// NavigationSplitView) for deterministic chart sizing.
struct WorkspaceView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @State private var showAbout = false
    @State private var showImporter = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let style = ChartStyle(display: workspace.display)

        VStack(spacing: 0) {
            toolbar(style: style)
            Divider().background(Color(white: 0.2))
            HStack(spacing: 0) {
                if workspace.sidebarVisible {
                    SidebarView(showImporter: $showImporter)
                        .frame(width: 300)
                        .transition(.move(edge: .leading))
                    Divider().background(Color(white: 0.2))
                }
                chartArea
                if workspace.inspectorVisible {
                    Divider().background(Color(white: 0.2))
                    InspectorView()
                        .frame(width: 340)
                        .transition(.move(edge: .trailing))
                }
            }
            Divider().background(Color(white: 0.2))
            hud
        }
        .background(Color.black.ignoresSafeArea())
        .tint(style.uiTint)
        .environment(\.chartStyle, style)
        .task { await workspace.start() }
        .sheet(isPresented: $showAbout) { AboutView() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data, .plainText]
        ) { result in
            if case .success(let url) = result {
                Task { await workspace.importUserCatalog(from: url) }
            }
        }
        .alert(
            "Enable catalog?",
            isPresented: pendingEnableBinding
        ) {
            Button("Enable and Show") {
                if let pending = workspace.pendingCatalogEnable {
                    workspace.updateSettings(
                        { $0.setVisible(true, catalog: pending.catalog) },
                        undoLabel: "Enable Catalog")
                    workspace.performActivation(pending.result)
                }
                workspace.pendingCatalogEnable = nil
            }
            Button("Go Without Enabling") {
                if let pending = workspace.pendingCatalogEnable {
                    workspace.performActivation(pending.result)
                }
                workspace.pendingCatalogEnable = nil
            }
            Button("Cancel", role: .cancel) {
                workspace.pendingCatalogEnable = nil
            }
        } message: {
            Text(
                "The result is in a catalog that is currently hidden. Enable the catalog to see the object on the chart?"
            )
        }
        .alert(
            "Import diagnostics",
            isPresented: importDiagnosticsBinding
        ) {
            Button("OK") { workspace.importDiagnostics = nil }
        } message: {
            Text(workspace.importDiagnostics ?? "")
        }
    }

    private var pendingEnableBinding: Binding<Bool> {
        Binding(
            get: { workspace.pendingCatalogEnable != nil },
            set: { if !$0 { workspace.pendingCatalogEnable = nil } })
    }

    private var importDiagnosticsBinding: Binding<Bool> {
        Binding(
            get: { workspace.importDiagnostics != nil },
            set: { if !$0 { workspace.importDiagnostics = nil } })
    }

    // MARK: toolbar

    private func toolbar(style: ChartStyle) -> some View {
        @Bindable var workspace = workspace
        return HStack(spacing: 14) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    workspace.sidebarVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .keyboardShortcut("b")
            .help("Toggle sidebar")
            .accessibilityLabel("Toggle sidebar")
            .accessibilityIdentifier("toolbar.sidebar")

            SearchField(focused: $searchFocused)
                .frame(maxWidth: 360)

            Spacer()

            Text(workspace.centerReadout)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("chart.centerReadout")

            Text(workspace.fieldReadout)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("chart.fieldReadout")

            Spacer()

            Button {
                workspace.zoomStep(in: true)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .keyboardShortcut("+")
            .help("Zoom in")
            .accessibilityLabel("Zoom in")
            .accessibilityIdentifier("toolbar.zoomIn")

            Button {
                workspace.zoomStep(in: false)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .keyboardShortcut("-")
            .help("Zoom out")
            .accessibilityLabel("Zoom out")
            .accessibilityIdentifier("toolbar.zoomOut")

            Toggle(isOn: $workspace.regionZoomArmed) {
                Image(systemName: "rectangle.dashed")
            }
            .toggleStyle(.button)
            .help("Zoom to a dragged region")
            .accessibilityLabel("Zoom region tool")
            .accessibilityIdentifier("toolbar.zoomRegion")

            Divider().frame(height: 18)

            Button {
                workspace.undoManager.undo()
                workspace.scheduleRebuild()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!workspace.undoManager.canUndo)
            .keyboardShortcut("z")
            .help("Undo")
            .accessibilityLabel("Undo")
            .accessibilityIdentifier("toolbar.undo")

            Button {
                workspace.undoManager.redo()
                workspace.scheduleRebuild()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!workspace.undoManager.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo")
            .accessibilityLabel("Redo")
            .accessibilityIdentifier("toolbar.redo")

            Divider().frame(height: 18)

            Toggle(isOn: nightModeBinding) {
                Image(systemName: "moon.fill")
            }
            .toggleStyle(.button)
            .help("Night mode")
            .accessibilityLabel("Night mode")
            .accessibilityIdentifier("toolbar.nightMode")

            Button {
                showAbout = true
            } label: {
                Image(systemName: "info.circle")
            }
            .help("About XSky")
            .accessibilityLabel("About")
            .accessibilityIdentifier("toolbar.about")

            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    workspace.inspectorVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .keyboardShortcut("i")
            .help("Toggle inspector")
            .accessibilityLabel("Toggle inspector")
            .accessibilityIdentifier("toolbar.inspector")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.07))
    }

    private var nightModeBinding: Binding<Bool> {
        Binding(
            get: { workspace.display.nightMode },
            set: { workspace.display.nightMode = $0 })
    }

    // MARK: chart

    @ViewBuilder
    private var chartArea: some View {
        ZStack {
            switch workspace.loadState {
            case .loading:
                ProgressView("Loading catalogs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            case .failed(let message):
                ContentUnavailableView(
                    "Catalogs failed to load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message))
            case .ready:
                ChartView()
            }

            if !workspace.searchResults.isEmpty {
                VStack {
                    SearchResultsList()
                        .frame(maxWidth: 430, maxHeight: 320)
                        .padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: HUD

    private var hud: some View {
        HStack(spacing: 20) {
            if workspace.regionZoomArmed {
                Label(
                    "Drag to select a region · Esc cancels",
                    systemImage: "rectangle.dashed")
                .font(.caption)
            }
            Spacer()
            if let hover = workspace.hoverReadout {
                Text(hover)
                    .font(.caption.monospacedDigit())
                    .accessibilityLabel("Pointer position")
            }
            Text(workspace.fieldReadout)
                .font(.caption.monospacedDigit())
            Text("Equinox J2000")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color(white: 0.07))
        .accessibilityElement(children: .combine)
    }
}

/// Style propagated to subviews so night mode reaches every surface.
private struct ChartStyleKey: EnvironmentKey {
    static let defaultValue = ChartStyle(display: DisplaySettings())
}

extension EnvironmentValues {
    var chartStyle: ChartStyle {
        get { self[ChartStyleKey.self] }
        set { self[ChartStyleKey.self] = newValue }
    }
}
