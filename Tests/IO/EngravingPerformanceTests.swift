import Dispatch
import Foundation
import Testing
@testable import MIDIKit

@Suite("Engraving release measurements", .serialized)
struct EngravingPerformanceTests {
    @Test(arguments: [1_000, 10_000])
    func measureBoundedEventWork(momentCount: Int) async throws {
        let reference = try EngravingReference(measures: [.init(index: 0, onset: 0, duration: Double(momentCount))],
            lines: [.init(index: 0, beatRange: 0...Double(momentCount), measureRange: 0...0)],
            moments: (0..<momentCount).map { i in
                .init(beat: Double(i), notes: [.init(pitch: UInt8(40 + i % 40), duration: 1, hand: .right)])
            })
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4
        var elapsed: [Double] = []
        var maximumStates = 0, maximumResiduals = 0, maximumExpansions = 0
        var lastBeat = -1.0
        var lateCommitments = 0
        for i in 0..<200 {
            let start = DispatchTime.now().uptimeNanoseconds
            let update = follower.consume(.noteOn(pitch: UInt8(40 + i % 40), velocity: 80),
                timestamp: UInt64((1 + Double(i) * 0.7) / EngravingHostTime.secondsPerTick))
            elapsed.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            if let update { lastBeat = update.beat }
            if lastBeat != Double(i) { lateCommitments += 1 }
            maximumStates = max(maximumStates, follower.diagnostics.paths)
            maximumResiduals = max(maximumResiduals, follower.diagnostics.residuals)
            maximumExpansions = max(maximumExpansions, follower.diagnostics.expansions)
        }
        elapsed.sort()
        #expect(maximumStates <= 128 && maximumResiduals <= 128 && maximumExpansions <= 4_096)
        #expect(lateCommitments <= 2, "A clear continuous trace must not pass by freezing")
        // Latency is reported, not asserted against a hardware-dependent wall-clock limit.
        print("ENGRAVING_METRICS moments=\(momentCount) events=200 p50_ms=\(elapsed[100]) p95_ms=\(elapsed[190]) p99_ms=\(elapsed[198]) max_ms=\(elapsed.last!) states=\(maximumStates) residuals=\(maximumResiduals) expansions=\(maximumExpansions) late_commitments=\(lateCommitments)")
    }
}
