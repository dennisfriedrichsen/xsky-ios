import SwiftUI
import XSkyCore

/// The sky chart: Canvas rendering plus pan, pinch, tap selection,
/// double-tap zoom, region zoom, hover, and context menu. During a
/// gesture the last snapshot is drawn through a cheap first-order
/// transform while exact rebuilds stream in; the gesture commits once at
/// its end and registers one undo entry.
struct ChartView: View {
    @Environment(WorkspaceModel.self) private var workspace

    @State private var dragAnchor: EquatorialCoordinate?
    @State private var pinchStartViewport: ChartViewport?
    @State private var regionRect: CGRect?
    @State private var lastInteractionPoint: CGPoint = .zero
    @State private var trekCursorPoint: CGPoint?
    @FocusState private var chartFocused: Bool

    var body: some View {
        let style = ChartStyle(display: workspace.display)

        canvas(style: style)
            .background(style.background)
            .overlay(alignment: .topLeading) { regionOverlay(style: style) }
            // X11 Trek Cursor (XC_trek, glyph 142): original X Window
            // System cursor font glyph, drawn in place of the system
            // pointer while a mouse or trackpad hovers the chart. See
            // AboutView for attribution. UIPointerInteraction has no
            // arbitrary-image style, so the system pointer is hidden and
            // this image tracks it instead.
            .overlay(alignment: .topLeading) { trekCursorOverlay }
            .hiddenSystemPointer()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                workspace.updateChartSize(size)
            }
            .gesture(workspace.regionZoomArmed ? nil : panGesture)
            .gesture(workspace.regionZoomArmed ? regionGesture : nil)
            .simultaneousGesture(pinchGesture)
            .simultaneousGesture(doubleTapGesture)
            .simultaneousGesture(singleTapGesture)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    let sky = ChartProjection.unproject(
                        Point2D(x: p.x, y: p.y), in: workspace.activeViewport)
                    let ra = SexagesimalRA(radians: sky.rightAscension)
                    let dec = SexagesimalDec(radians: sky.declination)
                    workspace.hoverReadout =
                        "\(ra.displayString)  \(dec.displayString)"
                    trekCursorPoint = p
                case .ended:
                    workspace.hoverReadout = nil
                    trekCursorPoint = nil
                }
            }
            .focusable()
            .focused($chartFocused)
            .focusEffectDisabled()
            .onKeyPress(action: handleKeyPress)
            .contextMenu { contextMenuItems }
            .accessibilityLabel("Sky chart")
            .accessibilityValue(accessibilitySummary)
            .accessibilityIdentifier("chart.canvas")
            // navigable list of the selected object and visible labels
            // (instead of thousands of invisible elements)
            .accessibilityChildren {
                if let details = workspace.selectedDetails {
                    Text("Selected: \(details.preferredName)")
                }
                ForEach(
                    workspace.snapshot?.labels ?? [], id: \.labelID
                ) { label in
                    Text(label.text)
                }
            }
            .onAppear { chartFocused = true }
    }

    // MARK: canvas

    private func canvas(style: ChartStyle) -> some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard let snapshot = workspace.snapshot else { return }
            let active = workspace.activeViewport

            if snapshot.viewport != active {
                // first-order preview: place the snapshot's center where
                // it falls in the active viewport and scale by the ratio
                let q = ChartProjection.project(
                    snapshot.viewport.center, in: active)
                let ratio =
                    snapshot.viewport.degreesPerPoint / active.degreesPerPoint
                context.translateBy(x: q.x, y: q.y)
                context.scaleBy(x: ratio, y: ratio)
                context.translateBy(
                    x: -snapshot.viewport.sizeInPoints.width / 2,
                    y: -snapshot.viewport.sizeInPoints.height / 2)
            }
            var ctx = context
            CanvasChartRenderer(style: style)
                .draw(snapshot, in: &ctx, size: size)
        }
    }

    // The trek glyph's hotspot (tip of the ship) sits at column 4 of 9,
    // row 0 of 16 in the source bitmap (see x11-trek.png).
    private static let trekCursorHotSpot = CGPoint(x: 4.5, y: 0.5)

    @ViewBuilder
    private var trekCursorOverlay: some View {
        if let p = trekCursorPoint {
            Image("X11Trek")
                .interpolation(.none)
                .allowsHitTesting(false)
                .offset(
                    x: p.x - Self.trekCursorHotSpot.x,
                    y: p.y - Self.trekCursorHotSpot.y)
        }
    }

    @ViewBuilder
    private func regionOverlay(style: ChartStyle) -> some View {
        if let rect = regionRect {
            Rectangle()
                .stroke(style.selectionColor, style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                .background(style.selectionColor.opacity(0.08))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }

    // MARK: gestures

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                lastInteractionPoint = value.location
                if dragAnchor == nil {
                    dragAnchor = ChartProjection.unproject(
                        Point2D(
                            x: value.startLocation.x,
                            y: value.startLocation.y),
                        in: workspace.viewport)
                }
                guard let anchor = dragAnchor else { return }
                // solve from the previous frame so each step stays
                // continuous (no 180-degree flip when crossing a pole)
                var vp = workspace.gestureViewport ?? workspace.viewport
                vp.center = ChartInteraction.centerKeeping(
                    anchor: anchor,
                    under: Point2D(x: value.location.x, y: value.location.y),
                    in: vp)
                workspace.gestureViewport = vp
                workspace.rebuildForGesturePreview()
            }
            .onEnded { _ in
                dragAnchor = nil
                if let vp = workspace.gestureViewport {
                    workspace.commitViewport(vp, undoLabel: "Pan")
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.02)
            .onChanged { value in
                if pinchStartViewport == nil {
                    pinchStartViewport = workspace.viewport
                }
                guard let start = pinchStartViewport else { return }
                let anchor = Point2D(
                    x: value.startAnchor.x * start.sizeInPoints.width,
                    y: value.startAnchor.y * start.sizeInPoints.height)
                workspace.gestureViewport = ChartInteraction.zoomedViewport(
                    start,
                    scaleFactor: 1 / max(0.05, value.magnification),
                    anchor: anchor)
                workspace.rebuildForGesturePreview()
            }
            .onEnded { _ in
                pinchStartViewport = nil
                if let vp = workspace.gestureViewport {
                    workspace.commitViewport(vp, undoLabel: "Zoom")
                }
            }
    }

    private var singleTapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                lastInteractionPoint = value.location
                guard !workspace.regionZoomArmed else { return }
                workspace.selectObject(
                    at: Point2D(x: value.location.x, y: value.location.y))
            }
    }

    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard !workspace.regionZoomArmed else { return }
                workspace.zoomStep(
                    in: true,
                    anchor: Point2D(x: value.location.x, y: value.location.y))
            }
    }

    private var regionGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                regionRect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.translation.width),
                    height: abs(value.translation.height))
            }
            .onEnded { _ in
                defer {
                    regionRect = nil
                    workspace.regionZoomArmed = false
                }
                guard let rect = regionRect, rect.width > 8, rect.height > 8
                else { return }
                workspace.commitViewport(
                    ChartInteraction.regionZoomedViewport(
                        workspace.viewport,
                        regionOrigin: Point2D(x: rect.minX, y: rect.minY),
                        regionSize: Size2D(
                            width: rect.width, height: rect.height)),
                    undoLabel: "Zoom Region")
            }
    }

    // MARK: keyboard

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        let step: Double = press.modifiers.contains(.shift) ? 200 : 60
        switch press.key {
        case .leftArrow:
            workspace.pan(byPoints: -step, 0)
        case .rightArrow:
            workspace.pan(byPoints: step, 0)
        case .upArrow:
            workspace.pan(byPoints: 0, -step)
        case .downArrow:
            workspace.pan(byPoints: 0, step)
        case .escape:
            if workspace.regionZoomArmed {
                workspace.regionZoomArmed = false
                regionRect = nil
            } else {
                workspace.selection = nil
            }
        default:
            return .ignored
        }
        return .handled
    }

    // MARK: context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        let point = Point2D(
            x: lastInteractionPoint.x, y: lastInteractionPoint.y)
        if let selection = workspace.selection {
            if workspace.hasLabel(forObject: selection) {
                Button("Remove Label") {
                    workspace.removeLabel(forObject: selection)
                }
            } else {
                Button("Add Label") {
                    workspace.addLabel(forObject: selection)
                }
            }
            Button("Center on Selection") {
                if let object = workspace.store?.object(selection) {
                    workspace.center(on: object.coordinate)
                }
            }
        }
        Button("Center Here") {
            workspace.center(
                on: ChartProjection.unproject(
                    point, in: workspace.activeViewport))
        }
        Button("Copy Coordinate") {
            let sky = ChartProjection.unproject(
                point, in: workspace.activeViewport)
            let ra = SexagesimalRA(radians: sky.rightAscension)
            let dec = SexagesimalDec(radians: sky.declination)
            UIPasteboard.general.string =
                "\(ra.displayString), \(dec.displayString)"
        }
    }

    private var accessibilitySummary: String {
        var parts = ["Centered at \(workspace.centerReadout)"]
        if let details = workspace.selectedDetails {
            parts.append("Selected: \(details.preferredName)")
        }
        return parts.joined(separator: ". ")
    }
}

extension View {
    /// Hides the system pointer while it hovers this view, so a custom
    /// cursor overlay can be drawn in its place.
    fileprivate func hiddenSystemPointer() -> some View {
        overlay(SystemPointerHidingArea().allowsHitTesting(false))
    }
}

/// UIPointerInteraction has no arbitrary-image style; `UIPointerStyle
/// .hidden()` is the closest public hook, so this bridges to it to hide
/// the system pointer for `hiddenSystemPointer()`.
private struct SystemPointerHidingArea: UIViewRepresentable {
    final class Coordinator: NSObject, UIPointerInteractionDelegate {
        func pointerInteraction(
            _ interaction: UIPointerInteraction,
            styleFor region: UIPointerRegion
        ) -> UIPointerStyle? {
            .hidden()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.addInteraction(UIPointerInteraction(delegate: context.coordinator))
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
