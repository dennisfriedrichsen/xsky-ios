import Foundation

/// A projected polyline in chart points.
public struct Polyline: Hashable, Sendable {
    public var points: [Point2D]

    public init(points: [Point2D]) {
        self.points = points
    }
}

/// One star ready to draw: position, diameter, and color class.
public struct RenderedStar: Hashable, Sendable {
    public var position: Point2D
    public var diameter: Double
    public var color: SpectralColorClass
    public var objectID: CatalogObjectID

    public init(
        position: Point2D, diameter: Double, color: SpectralColorClass,
        objectID: CatalogObjectID
    ) {
        self.position = position
        self.diameter = diameter
        self.color = color
        self.objectID = objectID
    }
}

/// One non-stellar object ready to draw.
public struct RenderedObject: Hashable, Sendable {
    public var position: Point2D
    public var symbol: ChartSymbol
    public var size: Double
    public var objectID: CatalogObjectID

    public init(
        position: Point2D, symbol: ChartSymbol, size: Double,
        objectID: CatalogObjectID
    ) {
        self.position = position
        self.symbol = symbol
        self.size = size
        self.objectID = objectID
    }
}

/// A label ready to draw: anchor point plus text offset in points.
public struct RenderedLabel: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case object
        case constellation
        case user
    }

    public var anchor: Point2D
    public var offset: Point2D
    public var text: String
    public var kind: Kind
    public var labelID: ChartLabelID

    public init(
        anchor: Point2D, offset: Point2D, text: String, kind: Kind,
        labelID: ChartLabelID
    ) {
        self.anchor = anchor
        self.offset = offset
        self.text = text
        self.kind = kind
        self.labelID = labelID
    }
}

/// The current selection, projected.
public struct RenderedSelection: Hashable, Sendable {
    public var position: Point2D
    public var objectID: CatalogObjectID

    public init(position: Point2D, objectID: CatalogObjectID) {
        self.position = position
        self.objectID = objectID
    }
}

/// Everything the renderer draws for one settled viewport. Contains only
/// projected coordinates and drawing semantics; safe to build off the
/// main actor and cheap to hand to the renderer.
public struct RenderSnapshot: Sendable {
    public var viewport: ChartViewport
    public var stars: [RenderedStar]
    public var objects: [RenderedObject]
    public var gridPaths: [Polyline]
    public var boundaryPaths: [Polyline]
    public var outlinePaths: [Polyline]
    public var labels: [RenderedLabel]
    public var selection: RenderedSelection?
    /// Monotonic build generation; stale snapshots never replace newer.
    public var generation: UInt64

    public init(
        viewport: ChartViewport,
        stars: [RenderedStar] = [],
        objects: [RenderedObject] = [],
        gridPaths: [Polyline] = [],
        boundaryPaths: [Polyline] = [],
        outlinePaths: [Polyline] = [],
        labels: [RenderedLabel] = [],
        selection: RenderedSelection? = nil,
        generation: UInt64 = 0
    ) {
        self.viewport = viewport
        self.stars = stars
        self.objects = objects
        self.gridPaths = gridPaths
        self.boundaryPaths = boundaryPaths
        self.outlinePaths = outlinePaths
        self.labels = labels
        self.selection = selection
        self.generation = generation
    }
}

/// Stable identity for a chart label.
public struct ChartLabelID: Hashable, Codable, Sendable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// A persistent chart label anchored in celestial coordinates with a text
/// offset in logical chart points (fixing the legacy screen-coordinate
/// user labels).
public struct ChartLabel: Hashable, Codable, Sendable, Identifiable {
    public enum Anchor: Hashable, Codable, Sendable {
        case object(CatalogObjectID)
        case constellation(Int)
        case sky(raRadians: Double, decRadians: Double)
    }

    public var id: ChartLabelID
    public var anchor: Anchor
    public var text: String
    /// Text offset from the anchor, in logical chart points.
    public var offsetX: Double
    public var offsetY: Double
    public var isHidden: Bool

    public init(
        id: ChartLabelID = ChartLabelID(),
        anchor: Anchor,
        text: String,
        offsetX: Double = 5,
        offsetY: Double = -3,
        isHidden: Bool = false
    ) {
        self.id = id
        self.anchor = anchor
        self.text = text
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.isHidden = isHidden
    }
}
