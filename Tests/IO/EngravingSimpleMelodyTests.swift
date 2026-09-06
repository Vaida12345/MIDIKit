import CoreMIDI
import Foundation
import Testing
@testable import MIDIKit

@Suite("Engraving familiar single-note melodies")
struct EngravingSimpleMelodyTests {
    struct Melody: Sendable, CustomTestStringConvertible {
        let name: String
        let pitches: [UInt8]
        let acquisitionDeadline: Int
        var testDescription: String { name }
    }

    static let melodies = [
        // The first seven pitches also occur in the second phrase. Attack seven is the
        // first pitch that distinguishes the two phrases without relying on the viewport.
        Melody(name: "Mary Had a Little Lamb", pitches: [64, 62, 60, 62, 64, 64, 64, 62, 62, 62, 64, 67, 67, 64, 62, 60, 62, 64, 64, 64, 64, 62, 62, 64, 62, 60], acquisitionDeadline: 7),
        Melody(name: "Twinkle opening", pitches: [60, 60, 67, 67, 69, 69, 67, 65, 65, 64, 64, 62, 62, 60, 67, 67, 65, 65, 64, 64, 62], acquisitionDeadline: 2),
        Melody(name: "Ode to Joy opening", pitches: [64, 64, 65, 67, 67, 65, 64, 62, 60, 60, 62, 64, 64, 62, 62], acquisitionDeadline: 2)
    ]

    private func reference(_ melody: Melody) throws -> EngravingReference {
        let measures = stride(from: 0, to: melody.pitches.count, by: 4).enumerated().map {
            EngravingReference.Measure(index: $0.offset, onset: Double($0.element), duration: 4)
        }
        let lines = stride(from: 0, to: measures.count, by: 2).enumerated().map {
            EngravingReference.Line(index: $0.offset,
                                    beatRange: Double($0.element * 4)...Double(min(measures.count, $0.element + 2) * 4),
                                    measureRange: $0.element...min(measures.count - 1, $0.element + 1))
        }
        return try EngravingReference(measures: measures, lines: lines, moments: melody.pitches.enumerated().map {
            .init(beat: Double($0.offset), notes: [.init(pitch: $0.element, duration: 1, hand: .right)])
        })
    }

    @Test(arguments: melodies, [0.25, 0.7, 1.4])
    func oneFingerMelody(melody: Melody, secondsPerBeat: Double) async throws {
        let reference = try reference(melody)
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...8
        var latest: EngravingScoreFollower.Update?
        for (i, pitch) in melody.pitches.enumerated() {
            let time = Double(i) * secondsPerBeat + 1
            if let update = follower.consume(.noteOn(pitch: pitch, velocity: 80), timestamp: ticks(time)) { latest = update }
            if i >= melody.acquisitionDeadline {
                #expect(latest?.beat == Double(i), "Correct attack \(i) must move the marker")
                #expect(latest?.displayBeat == Double(i))
                #expect(latest?.state == .tracking)
            }
            if let latest, latest.viewport != .unchanged {
                let line = reference.lines.first { $0.beatRange.contains(latest.beat) && latest.beat < $0.beatRange.upperBound }!
                follower.visibleRange = line.beatRange
            }
            if let update = follower.consume(.noteOff(pitch: pitch), timestamp: ticks(time + secondsPerBeat * 0.7)) { latest = update }
        }
    }

    @Test(arguments: melodies)
    func missingClockStillAcquiresAndFinishes(melody: Melody) async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try reference(melody))
        follower.visibleRange = 0...8
        var latest: EngravingScoreFollower.Update?
        for pitch in melody.pitches {
            if let update = follower.consume(.noteOn(pitch: pitch, velocity: 80), timestamp: 0) { latest = update }
            _ = follower.consume(.noteOff(pitch: pitch), timestamp: 0)
        }
        #expect(latest?.beat == Double(melody.pitches.count - 1))
        #expect(latest?.state == .tracking)
    }

    private func ticks(_ seconds: Double) -> MIDITimeStamp {
        MIDITimeStamp(seconds / EngravingHostTime.secondsPerTick)
    }
}
