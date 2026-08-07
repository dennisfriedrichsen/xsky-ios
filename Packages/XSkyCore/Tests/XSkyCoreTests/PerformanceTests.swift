import Foundation
import Testing

@testable import XSkyCore

@Suite("Performance and memory")
struct PerformanceTests {
    let store = CatalogTestSupport.store

    /// Cold catalog load (parse + index + search corpus) must comfortably
    /// beat the 2-second first-chart budget on its own.
    @Test func catalogLoadIsFast() throws {
        let start = ContinuousClock.now
        _ = try CatalogRepository.loadStore(
            locator: CatalogTestSupport.locator)
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .seconds(2), "cold load took \(elapsed)")
    }

    /// Memory stays bounded across 100 repeated pan/zoom scene rebuilds:
    /// no monotonic render-snapshot growth.
    @Test func repeatedRebuildsKeepMemoryBounded() {
        let builder = ChartSceneBuilder(store: store)
        var settings = ChartSettings()
        settings.showBoundaries = true
        settings.showOutlines = true

        func makeViewport(_ i: Int) -> ChartViewport {
            ChartViewport(
                center: EquatorialCoordinate(
                    rightAscension: Radians(
                        Double(i % 24) / 24 * 2 * .pi),
                    declination: Radians(
                        degrees: Double((i * 7) % 160) - 80)),
                degreesPerPoint: [0.01, 0.05, 0.2][i % 3],
                sizeInPoints: Size2D(width: 1366, height: 980))
        }

        // warm up and measure a baseline
        var snapshot = builder.buildSnapshot(
            viewport: makeViewport(0), settings: settings, labels: [],
            selection: nil, generation: 0)
        let baseline = Self.residentMemory()

        for i in 1...100 {
            snapshot = builder.buildSnapshot(
                viewport: makeViewport(i), settings: settings, labels: [],
                selection: nil, generation: UInt64(i))
        }
        #expect(!snapshot.stars.isEmpty || !snapshot.objects.isEmpty)

        let after = Self.residentMemory()
        let growth = after - baseline
        // replacing value-typed snapshots must not accumulate; allow slack
        // for allocator noise
        #expect(
            growth < 200 * 1024 * 1024,
            "resident memory grew by \(growth / 1024 / 1024) MB")
    }

    private static func residentMemory() -> Int64 {
        var info = mach_task_basic_info()
        var count =
            mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)
            / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0,
                    &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }
}
