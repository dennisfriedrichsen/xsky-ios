import SwiftUI
import XSkyCore

/// Renderer-facing style: all symbol/path/color choices live here.
/// Supports full color, monochrome, and red-on-black night mode.
struct ChartStyle {
    let colorMode: Bool
    let nightMode: Bool
    let labelScale: Double

    init(display: DisplaySettings) {
        colorMode = display.colorMode
        nightMode = display.nightMode
        labelScale = display.chartLabelScale
    }

    var background: Color { .black }

    /// Legacy spectral colors: O Blue, B DeepSkyBlue, A White,
    /// F NavajoWhite3, G Yellow, K Orange, M Red.
    func starColor(_ spectral: SpectralColorClass) -> Color {
        if nightMode { return nightForeground }
        guard colorMode else { return .white }
        switch spectral {
        case .o: return Color(red: 0.35, green: 0.45, blue: 1.0)
        case .b: return Color(red: 0.35, green: 0.75, blue: 1.0)
        case .a: return .white
        case .f: return Color(red: 0.80, green: 0.72, blue: 0.60)
        case .g: return Color(red: 1.0, green: 0.95, blue: 0.30)
        case .k: return Color(red: 1.0, green: 0.65, blue: 0.15)
        case .m: return Color(red: 1.0, green: 0.30, blue: 0.25)
        case .neutral: return .white
        }
    }

    var nightForeground: Color { Color(red: 0.95, green: 0.15, blue: 0.10) }

    var objectSymbolColor: Color {
        nightMode ? nightForeground : Color(red: 0.55, green: 0.85, blue: 0.65)
    }

    var gridColor: Color {
        nightMode
            ? nightForeground.opacity(0.35)
            : Color(red: 0.28, green: 0.32, blue: 0.42)
    }

    var boundaryColor: Color {
        nightMode
            ? nightForeground.opacity(0.45)
            : Color(red: 0.45, green: 0.38, blue: 0.22)
    }

    var outlineColor: Color {
        nightMode
            ? nightForeground.opacity(0.55)
            : Color(red: 0.30, green: 0.50, blue: 0.60)
    }

    var labelColor: Color {
        nightMode ? nightForeground : Color(white: 0.92)
    }

    var constellationLabelColor: Color {
        nightMode ? nightForeground.opacity(0.8) : Color(white: 0.65)
    }

    var selectionColor: Color {
        nightMode ? nightForeground : Color(red: 0.35, green: 0.80, blue: 1.0)
    }

    var labelFontSize: Double { 11 * max(0.7, labelScale) }
    var constellationLabelFontSize: Double { 13 * max(0.7, labelScale) }

    /// UI accent for controls when night mode is active.
    var uiTint: Color? { nightMode ? nightForeground : nil }
}
