import Foundation
import Testing
@testable import MIDIKit

@Suite("Engraving conservative search")
struct EngravingSearchTests {
    private func reference(_ pitches: [UInt8]) throws -> EngravingScoreIndex {
        EngravingScoreIndex(try EngravingReference(measures: [.init(index: 0, onset: 0, duration: Double(pitches.count))],
            lines: [.init(index: 0, beatRange: 0...Double(pitches.count), measureRange: 0...0)],
            moments: pitches.enumerated().map { .init(beat: Double($0.offset), notes: [.init(pitch: $0.element, duration: 1, hand: .right)]) }))
    }

    @Test(arguments: [[UInt8(60), 62, 64], [60, 60, 62], [99, 60, 64], [64, 62, 60]])
    func boundedSupportDoesNotExceedExhaustiveSupport(events: [UInt8]) throws {
        let score = try reference([60, 62, 60, 64, 62, 60])
        var bounded = EngravingFilter()
        bounded.limits.hypotheses = 4
        bounded.limits.perDestination = 2
        bounded.limits.destinations = 2
        bounded.limits.expansions = 256
        var exhaustive = EngravingFilter()
        exhaustive.limits.hypotheses = 50_000
        exhaustive.limits.perDestination = 50_000
        exhaustive.limits.destinations = score.moments.count
        exhaustive.limits.expansions = 1_000_000
        exhaustive.limits.residuals = 50_000
        var input = EngravingInputState()
        for pitch in events {
            let observation = input.consume(.noteOn(pitch: pitch, velocity: 80), timestamp: 0)
            let lower = bounded.consume(observation, score: score, calibration: .init(), lost: false)
            let exact = exhaustive.consume(observation, score: score, calibration: .init(), lost: false)
            #expect(exhaustive.residuals.isEmpty, "The oracle must not prune or truncate retrieval")
            for destination in score.moments.indices {
                #expect(lower.exact(destination) <= exact.exact(destination) + 1e-10)
            }
        }
    }

    @Test func serializedChordHasNoMultipleOnsetCertificate() throws {
        let reference = try EngravingReference(measures: [.init(index: 0, onset: 0, duration: 2)],
            lines: [.init(index: 0, beatRange: 0...2, measureRange: 0...0)], moments: [
                .init(beat: 0, notes: [UInt8(60), 64, 67, 71].map { .init(pitch: $0, duration: 1, hand: .right) }),
                .init(beat: 1, notes: [.init(pitch: 72, duration: 1, hand: .right)])
            ])
        let score = EngravingScoreIndex(reference)
        var input = EngravingInputState(), filter = EngravingFilter()
        for pitch in [UInt8(60), 64, 67, 70, 71] {
            let event = input.consume(.noteOn(pitch: pitch, velocity: 90), timestamp: 0)
            let evidence = filter.consume(event, score: score, calibration: .init(), lost: false)
            #expect(evidence.paths.allSatisfy { $0.path.onsets == 1 })
        }
    }

    @Test func burstsDoNotGrowMutableStateOrWork() throws {
        let score = try reference(Array(repeating: [UInt8(60), 62, 64, 65], count: 300).flatMap { $0 })
        var filter = EngravingFilter(), input = EngravingInputState()
        for i in 0..<400 {
            let event = input.consume(.noteOn(pitch: UInt8(60 + i % 6), velocity: 80), timestamp: 0)
            let evidence = filter.consume(event, score: score, calibration: .init(), lost: false)
            #expect(filter.paths.count <= 128)
            #expect(filter.residuals.count <= 128)
            #expect(filter.history.count <= 256)
            #expect(filter.expansions <= 4_096)
            #expect(filter.destinations <= 64)
            #expect(evidence.totalLogMass.isFinite)
        }
    }

    @Test(arguments: [[UInt8(60), 64, 62], [60, 62, 64], [64, 67, 70], [60, 70, 65]])
    func polyphonicBoundsRemainBelowExhaustiveInference(events: [UInt8]) throws {
        let score = EngravingScoreIndex(try EngravingReference(measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)], moments: [
                [UInt8(60), 64], [62, 65], [64, 67], [60, 70]
            ].enumerated().map { i, pitches in .init(beat: Double(i), notes: pitches.enumerated().map {
                .init(pitch: $0.element, duration: 1, hand: $0.offset == 0 ? .left : .right)
            }) }))
        var bounded = EngravingFilter(), exhaustive = EngravingFilter(), input = EngravingInputState()
        bounded.limits.hypotheses = 4
        bounded.limits.perDestination = 2
        bounded.limits.destinations = 2
        exhaustive.limits.hypotheses = 50_000
        exhaustive.limits.perDestination = 50_000
        exhaustive.limits.destinations = 4
        exhaustive.limits.expansions = 1_000_000
        for (i, pitch) in events.enumerated() {
            let event = input.consume(.noteOn(pitch: pitch, velocity: 80), timestamp: UInt64((1 + Double(i) * 0.05) / EngravingHostTime.secondsPerTick))
            let bound = bounded.consume(event, score: score, calibration: .init(), lost: false)
            let exact = exhaustive.consume(event, score: score, calibration: .init(), lost: false)
            #expect(exhaustive.residuals.isEmpty)
            for destination in score.moments.indices { #expect(bound.exact(destination) <= exact.exact(destination) + 1e-10) }
        }
    }
}
