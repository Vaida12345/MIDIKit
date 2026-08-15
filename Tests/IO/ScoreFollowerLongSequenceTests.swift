//
//  ScoreFollowerLongSequenceTests.swift
//  MIDIKit
//
//  Created by Codex on 2026-08-15.
//
//  Summary: Deterministic randomized long-form score-following coverage.
//

import CoreMIDI
import Testing
@testable import MIDIKit


@Suite("Score follower long sequences")
struct ScoreFollowerLongSequenceTests {

    /// Verifies that a long, randomized tonal progression remains aligned for several reproducible scores.
    @Test("follows randomized real-life-length chord progressions")
    func followsRandomizedChordProgressions() async {
        for seed in [UInt64(0xC0FFEE), 0xBAD5EED, 0xFACEFEED] {
            let chords = makeChordProgression(seed: seed, momentCount: 128)
            let follower = ScoreFollower()
            await follower.update(
                referenceMoments: chords.enumerated().map { index, pitches in
                    .init(beat: Double(index), pitches: Set(pitches))
                }
            )

            let positions = consume(chords, with: follower, seed: seed)

            #expect(
                positions.map(\.beat)
                    == chords.indices.flatMap { index in
                        Array(repeating: Double(index), count: chords[index].count)
                    }
            )
        }
    }

    /// Verifies that a dense, randomized score remains practical to follow at live-input speed.
    @Test("processes a dense randomized chord progression promptly")
    func processesDenseRandomizedChordProgressionPromptly() async {
        let chords = makeChordProgression(seed: 0xDECADE, momentCount: 256)
        let follower = ScoreFollower()
        await follower.update(
            referenceMoments: chords.enumerated().map { index, pitches in
                .init(beat: Double(index), pitches: Set(pitches))
            }
        )

        let clock = ContinuousClock()
        let start = clock.now
        let positions = consume(chords, with: follower, seed: 0xDECADE)
        let elapsed = start.duration(to: clock.now)

        #expect(positions.last?.beat == 255)
        #expect(elapsed < .seconds(1))
    }

    /// Creates a reproducible, tonal progression with varied inversions and chord sizes.
    private func makeChordProgression(seed: UInt64, momentCount: Int) -> [[UInt8]] {
        let scale = [0, 2, 4, 5, 7, 9, 11]
        let qualities = [[0, 4, 7], [0, 3, 7], [0, 3, 6]]
        var generator = LinearCongruentialGenerator(seed: seed)
        var degree = generator.nextInt(upperBound: scale.count)

        return (0..<momentCount).map { _ in
            degree = (degree + [1, 2, 4, 5, 6][generator.nextInt(upperBound: 5)]) % scale.count
            let root = 48 + scale[degree]
            let quality = qualities[generator.nextInt(upperBound: qualities.count)]
            let octave = generator.nextInt(upperBound: 3) == 0 ? [12] : []
            let inversion = generator.nextInt(upperBound: quality.count)

            return (quality + octave)
                .map { UInt8(root + $0) }
                .rotatedLeft(by: inversion)
        }
    }

    /// Feeds each chord in a reproducible shuffled order and records every inferred position.
    private func consume(
        _ chords: [[UInt8]],
        with follower: ScoreFollower,
        seed: UInt64
    ) -> [ScoreFollower.Position] {
        var generator = LinearCongruentialGenerator(seed: seed ^ 0x9E3779B97F4A7C15)
        var timestamp: MIDITimeStamp = 1_000
        var positions: [ScoreFollower.Position] = []

        for chord in chords {
            for pitch in chord.shuffled(using: &generator) {
                if let position = follower.consume(noteOn: pitch, timestamp: timestamp) {
                    positions.append(position)
                }
                timestamp += 1_000
            }
        }

        return positions
    }


    /// A small deterministic random-number generator suitable for reproducible tests.
    private struct LinearCongruentialGenerator: RandomNumberGenerator {
        private var state: UInt64

        /// Creates the generator with a nonzero deterministic seed.
        init(seed: UInt64) {
            state = seed == 0 ? 1 : seed
        }

        /// Produces the next pseudo-random value.
        mutating func next() -> UInt64 {
            state = 2_862_933_555_777_941_757 &* state &+ 3_037_000_493
            return state
        }

        /// Produces a pseudo-random integer below the supplied exclusive bound.
        mutating func nextInt(upperBound: Int) -> Int {
            Int(next() % UInt64(upperBound))
        }
    }
}


private extension Array {
    /// Rotates the array left by a count less than or equal to its length.
    func rotatedLeft(by count: Int) -> [Element] {
        guard !isEmpty else { return self }
        let offset = count % self.count
        return Array(self[offset...] + self[..<offset])
    }
}
