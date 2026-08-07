import SwiftUI
import XSkyCore

/// Draws an immutable render snapshot into a GraphicsContext. Layer
/// order: objects, grid, boundaries, outlines, labels, selection (with
/// stars beneath the non-stellar objects inside the first layer).
struct CanvasChartRenderer {
    let style: ChartStyle

    func draw(
        _ snapshot: RenderSnapshot, in context: inout GraphicsContext,
        size: CGSize
    ) {
        drawStars(snapshot.stars, in: &context)
        drawObjects(snapshot.objects, in: &context)
        stroke(snapshot.gridPaths, color: style.gridColor, width: 0.75, in: &context)
        stroke(
            snapshot.boundaryPaths, color: style.boundaryColor, width: 1,
            in: &context, dash: [4, 3])
        stroke(
            snapshot.outlinePaths, color: style.outlineColor, width: 1.25,
            in: &context)
        drawLabels(snapshot.labels, in: &context)
        drawSelection(snapshot.selection, in: &context)
    }

    // MARK: layers

    private func drawStars(
        _ stars: [RenderedStar], in context: inout GraphicsContext
    ) {
        // batch by color class to minimize fill-style changes
        var batches: [SpectralColorClass: Path] = [:]
        for star in stars {
            let d = star.diameter
            let rect = CGRect(
                x: star.position.x - d / 2, y: star.position.y - d / 2,
                width: d, height: d)
            batches[star.color, default: Path()].addEllipse(in: rect)
        }
        for (color, path) in batches {
            context.fill(path, with: .color(style.starColor(color)))
        }
    }

    private func drawObjects(
        _ objects: [RenderedObject], in context: inout GraphicsContext
    ) {
        var paths: [ChartSymbol: Path] = [:]
        for object in objects {
            paths[object.symbol, default: Path()].addPath(
                Self.symbolPath(
                    object.symbol, at: object.position, size: object.size))
        }
        for (_, path) in paths {
            context.stroke(
                path, with: .color(style.objectSymbolColor),
                style: StrokeStyle(lineWidth: 1.25))
        }
    }

    static func symbolPath(
        _ symbol: ChartSymbol, at p: Point2D, size: Double
    ) -> Path {
        var path = Path()
        let h = size / 2
        let rect = CGRect(x: p.x - h, y: p.y - h, width: size, height: size)
        switch symbol {
        case .star:
            path.addEllipse(in: rect)
        case .ellipse:
            path.addEllipse(
                in: CGRect(
                    x: p.x - h * 1.4, y: p.y - h * 0.75, width: size * 1.4,
                    height: size * 0.75))
        case .circle:
            path.addEllipse(in: rect)
        case .crossedCircle:
            path.addEllipse(in: rect)
            let d = h * 0.7071
            path.move(to: CGPoint(x: p.x - d, y: p.y - d))
            path.addLine(to: CGPoint(x: p.x + d, y: p.y + d))
            path.move(to: CGPoint(x: p.x + d, y: p.y - d))
            path.addLine(to: CGPoint(x: p.x - d, y: p.y + d))
        case .square:
            path.addRect(rect)
        case .diamond:
            path.move(to: CGPoint(x: p.x, y: p.y - h))
            path.addLine(to: CGPoint(x: p.x + h, y: p.y))
            path.addLine(to: CGPoint(x: p.x, y: p.y + h))
            path.addLine(to: CGPoint(x: p.x - h, y: p.y))
            path.closeSubpath()
        case .xMark:
            path.move(to: CGPoint(x: p.x - h, y: p.y - h))
            path.addLine(to: CGPoint(x: p.x + h, y: p.y + h))
            path.move(to: CGPoint(x: p.x + h, y: p.y - h))
            path.addLine(to: CGPoint(x: p.x - h, y: p.y + h))
        }
        return path
    }

    private func stroke(
        _ polylines: [Polyline], color: Color, width: Double,
        in context: inout GraphicsContext, dash: [CGFloat] = []
    ) {
        guard !polylines.isEmpty else { return }
        var path = Path()
        for line in polylines {
            guard let first = line.points.first else { continue }
            path.move(to: CGPoint(x: first.x, y: first.y))
            for p in line.points.dropFirst() {
                path.addLine(to: CGPoint(x: p.x, y: p.y))
            }
        }
        context.stroke(
            path, with: .color(color),
            style: StrokeStyle(lineWidth: width, dash: dash))
    }

    private func drawLabels(
        _ labels: [RenderedLabel], in context: inout GraphicsContext
    ) {
        for label in labels {
            let isConstellation = label.kind == .constellation
            let font = Font.system(
                size: isConstellation
                    ? style.constellationLabelFontSize : style.labelFontSize,
                weight: isConstellation ? .semibold : .regular,
                design: .rounded)
            let color =
                isConstellation ? style.constellationLabelColor : style.labelColor
            var text = context.resolve(
                Text(label.text).font(font).foregroundStyle(color))
            text.shading = .color(color)
            let position = CGPoint(
                x: label.anchor.x + label.offset.x,
                y: label.anchor.y + label.offset.y)
            let anchor: UnitPoint = isConstellation ? .center : .topLeading
            // dark halo keeps labels readable over symbols and lines
            let measured = text.measure(in: CGSize(width: 400, height: 60))
            let backdrop = CGRect(
                origin: CGPoint(
                    x: position.x - (anchor == .center ? measured.width / 2 : 0) - 2,
                    y: position.y - (anchor == .center ? measured.height / 2 : 0) - 1),
                size: CGSize(width: measured.width + 4, height: measured.height + 2))
            context.fill(
                Path(roundedRect: backdrop, cornerRadius: 3),
                with: .color(.black.opacity(0.55)))
            context.draw(text, at: position, anchor: anchor)
        }
    }

    private func drawSelection(
        _ selection: RenderedSelection?, in context: inout GraphicsContext
    ) {
        guard let selection else { return }
        let p = selection.position
        let r: Double = 12
        var ring = Path()
        ring.addEllipse(
            in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        context.stroke(
            ring, with: .color(style.selectionColor),
            style: StrokeStyle(lineWidth: 1.5))
        var cross = Path()
        for (dx, dy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
            cross.move(to: CGPoint(x: p.x + dx * (r + 2), y: p.y + dy * (r + 2)))
            cross.addLine(
                to: CGPoint(x: p.x + dx * (r + 7), y: p.y + dy * (r + 7)))
        }
        context.stroke(
            cross, with: .color(style.selectionColor),
            style: StrokeStyle(lineWidth: 1.5))
    }
}
