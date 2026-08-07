import Foundation
import XSkyCore

/// Decoded golden fixture data generated from the legacy C implementation
/// by tools/golden/generate.sh. See Fixtures/README.md.
struct GoldenFixtures: Decodable {
    struct ForwardProjection: Decodable {
        let display: String
        let point: String
        let x: Double
        let y: Double
    }

    struct InverseProjection: Decodable {
        let display: String
        let px: Int
        let py: Int
        let ra: Double
        let dec: Double
    }

    struct DisplayLimits: Decodable {
        let display: String
        let leftRA: Double
        let rightRA: Double
        let topDec: Double
        let bottomDec: Double
    }

    struct WithinLimits: Decodable {
        let display: String
        let point: String
        let inside: Bool
    }

    struct Precession: Decodable {
        let from: Double
        let to: Double
        let point: String
        let ra: Double
        let dec: Double
    }

    struct HergetPrecession: Decodable {
        let point: String
        let ra: Double
        let dec: Double
    }

    struct Constellation: Decodable {
        let point: String
        let constellation: String
    }

    struct RAParse: Decodable {
        let input: String
        let h: Int?
        let m: Int?
        let s: Int?
        let thousandths: Int?
        let radians: Double?
        let invalid: Bool?
    }

    struct DecParse: Decodable {
        let input: String
        let sign: Int?
        let d: Int?
        let m: Int?
        let s: Int?
        let hundredths: Int?
        let radians: Double?
        let invalid: Bool?
    }

    struct RAFormat: Decodable {
        let radians: Double
        let h: Int
        let m: Int
        let s: Int
        let thousandths: Int
    }

    struct DecFormat: Decodable {
        let radians: Double
        let sign: Int
        let d: Int
        let m: Int
        let s: Int
        let hundredths: Int
    }

    let forwardProjection: [ForwardProjection]
    let inverseProjection: [InverseProjection]
    let displayLimits: [DisplayLimits]
    let withinLimits: [WithinLimits]
    let precession: [Precession]
    let hergetPrecession: [HergetPrecession]
    let constellation: [Constellation]
    let raParse: [RAParse]
    let decParse: [DecParse]
    let raFormat: [RAFormat]
    let decFormat: [DecFormat]

    static let shared: GoldenFixtures = {
        guard
            let url = Bundle.module.url(
                forResource: "golden", withExtension: "json",
                subdirectory: "Fixtures")
        else {
            fatalError("golden.json fixture missing from test bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(GoldenFixtures.self, from: data)
        } catch {
            fatalError("golden.json failed to decode: \(error)")
        }
    }()
}

/// The test display and point definitions mirroring goldengen.c.
enum GoldenInputs {
    static let points: [String: (ra: Double, dec: Double)] = [
        "center_orion": (1.4665923398, -0.0209621934),
        "sirius": (1.7677953696, -0.2917512740),
        "betelgeuse": (1.5497291380, 0.1292776940),
        "m31": (0.1863402843, 0.7202828960),
        "polaris": (0.6624317181, 1.5579526427),
        "sgr_a": (4.6498570863, -0.5062817157),
        "ra_wrap_low": (0.0087266463, -0.1745329252),
        "ra_wrap_high": (6.2657320146, -0.1745329252),
        "south_pole_ish": (3.6651914292, -1.5533430343),
        "equator_12h": (3.1415926536, 0.0),
    ]

    static let displays: [String: ChartViewport] = {
        func vp(
            _ w: Double, _ h: Double, _ scale: Double, _ down: Bool,
            _ ra: Double, _ dec: Double
        ) -> ChartViewport {
            // legacy display->scale was a C float; reproduce its rounding
            // so fixture comparisons are exact rather than approximate
            ChartViewport(
                center: EquatorialCoordinate(
                    rightAscension: Radians(ra), declination: Radians(dec)),
                degreesPerPoint: Double(Float(scale)),
                sizeInPoints: Size2D(width: w, height: h),
                orientation: down ? .downunder : .normal)
        }
        return [
            "orion_default": vp(400, 400, 0.05, false, 1.4665923398, -0.0209621934),
            "orion_downunder": vp(400, 400, 0.05, true, 1.4665923398, -0.0209621934),
            "near_north_pole": vp(800, 600, 0.1, false, 0.05, 1.5358897417),
            "ra_wrap": vp(1024, 768, 0.2, false, 6.1959188445, -0.5235987756),
            "wide_field": vp(400, 400, 0.5, false, 3.1415926536, 0.0),
            "narrow_polaris": vp(500, 400, 0.001, false, 0.6624317181, 1.5579526427),
            "south_downunder": vp(640, 480, 0.15, true, 4.7123889804, -1.2217304764),
        ]
    }()
}
