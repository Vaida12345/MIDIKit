import CoreMIDI
import Foundation
import Dispatch
import Testing
@testable import MIDIKit

@Suite("Engraving ordinary chord continuity", .serialized)
struct EngravingChordContinuityTests {
    static let chords: [[UInt8]] = [
        [48, 60, 64, 67], [53, 60, 65, 69], [55, 59, 62, 67], [57, 60, 64, 69],
        [50, 62, 65, 69], [55, 59, 62, 67], [52, 59, 64, 67], [48, 60, 64, 67],
        [53, 60, 65, 69], [50, 62, 65, 69], [55, 59, 62, 67], [48, 60, 64, 67]
    ]

    @Test func reliableAcquisitionCanPublishBeforeTrackingConfidence() async throws {
        let pitches: [[UInt8]] = [[60], [72], [74], [60, 64]]
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: pitches.enumerated().map { i, chord in
                .init(beat: Double(i), notes: chord.map { .init(pitch: $0, duration: 1, hand: .right) })
            })
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...2
        let acquisition = try #require(follower.consume(.noteOn(pitch: 60, velocity: 80), timestamp: ticks(1)))
        #expect(acquisition.beat == 0 && acquisition.displayBeat == 0)
        #expect(acquisition.confidence >= 0.80 && acquisition.confidence < 0.90)
        #expect(acquisition.state == .uncertain && acquisition.viewport == .unchanged)
        let following = try #require(follower.consume(.noteOn(pitch: 72, velocity: 80), timestamp: ticks(1.8)))
        #expect(following.beat == 1 && following.state == .tracking)
    }

    @Test func aFullPageOfChordsDoesNotFreeze() async throws {
        try await run(chords: Array(repeating: Self.chords, count: 3).flatMap { $0 }, spread: 0.012, upperHandFirst: true)
    }

    @Test func bothOverloadsFollowTheSameChords() async throws {
        try await run(chords: Self.chords, spread: 0.012, upperHandFirst: true, verifyOverloads: true)
    }

    @Test func establishedChordsKeepTheNextLineReadable() async throws {
        var chords = Array(repeating: Self.chords, count: 6).flatMap { $0 }
        chords[0] = [36, 72, 76, 79]
        chords[1] = [37, 73, 77, 80]
        chords[2] = [38, 74, 78, 81]
        try await run(chords: chords, spread: 0.012, upperHandFirst: true, requireAdvances: true)
    }

    @Test(arguments: [false, true], [false, true])
    func chordViewportWorksWithEitherClockAndReleaseConvention(clockAvailable: Bool, releaseNotes: Bool) async throws {
        try await run(chords: Self.chords, spread: 0.012, upperHandFirst: true,
                      requireAdvances: true, clockAvailable: clockAvailable, releaseNotes: releaseNotes)
    }

    @Test(arguments: [2, 8])
    func ordinaryChordsScrollAcrossDifferentLineLengths(perLine: Int) async throws {
        var chords = Self.chords + Self.chords
        chords[0] = [36, 72, 76, 79] // Distinguishes the occurrence before testing layout policy.
        try await run(chords: chords, spread: 0.012, upperHandFirst: true,
                      requireAdvances: true, perLine: perLine)
    }

    @Test(arguments: [2, 3, 6])
    func differentChordSizesFollowNormally(size: Int) async throws {
        let voicing: [UInt8] = [36, 48, 60, 64, 67, 72]
        let chords = (0..<12).map { i in voicing.prefix(size).map { $0 + UInt8(i) } }
        try await run(chords: chords, spread: 0.012, upperHandFirst: true, requireAdvances: true)
    }

    @Test(arguments: [0.0, 0.012, 0.06], [false, true])
    func cleanChordsKeepFollowing(spread: Double, upperHandFirst: Bool) async throws {
        try await run(chords: Self.chords, spread: spread, upperHandFirst: upperHandFirst)
    }

    private func run(chords: [[UInt8]], spread: Double, upperHandFirst: Bool, verifyOverloads: Bool = false, requireAdvances: Bool = false, clockAvailable: Bool = true, releaseNotes: Bool = true, perLine: Int = 4) async throws {
        let reference = try EngravingReference(
            measures: (0..<(chords.count / perLine)).map { .init(index: $0, onset: Double($0 * perLine), duration: Double(perLine)) },
            lines: (0..<(chords.count / perLine)).map { .init(index: $0, beatRange: Double($0 * perLine)...Double(($0 + 1) * perLine), measureRange: $0...$0) },
            moments: chords.enumerated().map { i, pitches in
                .init(beat: Double(i), notes: pitches.enumerated().map { j, pitch in
                    .init(pitch: pitch, duration: 0.8, hand: j == 0 ? .left : .right)
                })
            })
        let engraving = EngravingScoreFollower()
        let original = ScoreFollower()
        let wrapped = verifyOverloads ? EngravingScoreFollower() : nil
        await wrapped?.update(reference: reference)
        wrapped?.visibleRange = 0...Double(perLine)
        var latency: [Double] = []
        var peakResiduals = 0
        var advances = 0
        await engraving.update(reference: reference)
        await original.update(referenceMoments: chords.enumerated().map { .init(beat: Double($0.offset), pitches: Set($0.element)) })
        engraving.visibleRange = 0...Double(perLine)
        var latest: EngravingScoreFollower.Update?
        for (i, chord) in chords.enumerated() {
            let ordered = upperHandFirst ? Array(chord.reversed()) : chord
            for (j, pitch) in ordered.enumerated() {
                let time = 1 + Double(i) * 0.8 + Double(j) * spread
                let event = ParsedInputEvent.noteOn(pitch: pitch, velocity: 80)
                let start = DispatchTime.now().uptimeNanoseconds
                let result = engraving.consume(event, timestamp: clockAvailable ? ticks(time) : 0)
                latency.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                peakResiduals = max(peakResiduals, engraving.diagnostics.residuals)
                #expect(engraving.diagnostics.paths <= 128 && engraving.diagnostics.residuals <= EngravingLimits().residuals)
                #expect(engraving.diagnostics.expansions <= 4_096 && engraving.diagnostics.destinations <= 64)
                if let wrapped {
                    #expect(wrapped.consume(MIDIInputEvent(timestamp: clockAvailable ? ticks(time) : 0, event: event, channel: 0)) == result)
                }
                if let update = result {
                    latest = update
                    if requireAdvances { #expect(!update.didReframe, "Continuous clean playing needs ordinary advances") }
                    if update.viewport != .unchanged {
                        if case .advance = update.viewport { advances += 1 }
                        engraving.visibleRange = Double(i / perLine * perLine)...Double((i / perLine + 1) * perLine)
                        wrapped?.visibleRange = engraving.visibleRange
                    }
                }
                _ = original.consume(MIDIInputEvent(timestamp: clockAvailable ? ticks(time) : 0, event: event, channel: 0))
            }
            #expect(original.lastPosition?.beat == Double(i), "Ordinary reference follower establishes the comparison")
            if i >= 2 {
                #expect(latest?.beat == Double(i), "Every fully played chord must be followed by its final attack")
                #expect(latest?.state == .tracking)
                #expect(latest?.activeHands == .both)
                #expect(latest?.displayBeat == Double(i))
                if requireAdvances {
                    #expect(engraving.visibleRange?.contains(Double(i)) == true, "Reveal each line by the final attack of its entered chord")
                    #expect(engraving.visibleRange!.upperBound > Double(i))
                }
            }
            for pitch in releaseNotes ? chord : [] {
                let event = ParsedInputEvent.noteOff(pitch: pitch)
                let result = engraving.consume(event, timestamp: ticks(1 + Double(i) * 0.8 + 0.6))
                if let wrapped {
                    #expect(wrapped.consume(MIDIInputEvent(timestamp: ticks(1 + Double(i) * 0.8 + 0.6), event: event, channel: 0)) == result)
                }
                _ = original.consume(MIDIInputEvent(timestamp: ticks(1 + Double(i) * 0.8 + 0.6), event: event, channel: 0))
            }
        }
        if requireAdvances {
            #expect(advances > 0, "Must issue actual viewport recommendations through the public API")
            latency.sort()
            print("ENGRAVING_CHORD_METRICS chords=\(chords.count) attacks=\(latency.count) p50_ms=\(latency[latency.count / 2]) p95_ms=\(latency[latency.count * 95 / 100]) p99_ms=\(latency[latency.count * 99 / 100]) max_ms=\(latency.last!) residuals=\(peakResiduals)")
        }
    }

    private func ticks(_ seconds: Double) -> MIDITimeStamp { MIDITimeStamp(seconds / EngravingHostTime.secondsPerTick) }
}
