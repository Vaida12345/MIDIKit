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

    /// Verifies that a brief, distinctive fragment of a similar later passage cannot override continuity.
    @Test("does not jump to a similar later passage on weak evidence")
    func doesNotJumpToSimilarLaterPassageOnWeakEvidence() async {
        let passages = similarPassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: referenceMoments(for: passages))

        _ = consume(Array(passages.0.prefix(8)), with: follower, startingAt: 1_000)
        let positions = consume(Array(passages.1.suffix(2)), with: follower, startingAt: 100_000)

        #expect(!positions.contains { $0.didJump })
        #expect(follower.lastPosition?.beat ?? 0 < 20)
    }

    /// Verifies that intermittent wrong notes resembling a later cadence do not trigger a false jump.
    @Test("does not jump when mistakes resemble a later passage")
    func doesNotJumpWhenMistakesResembleLaterPassage() async {
        let passages = similarPassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: referenceMoments(for: passages))

        let performedChords = Array(passages.0.prefix(8)) + [
            [41, 48, 53, 60], [43, 50, 55, 60], [45, 52, 57, 62], [47, 54, 59, 64]
        ]
        let positions = consume(performedChords, with: follower, startingAt: 1_000)

        #expect(!positions.contains { $0.didJump })
        #expect(follower.lastPosition?.beat ?? 0 < 20)
    }

    /// Reproduces a false passage switch caused by small top-voice mistakes that resemble a later repeat.
    @Test("does not bounce between near-duplicate passages after small mistakes")
    func doesNotBounceBetweenNearDuplicatePassagesAfterSmallMistakes() async {
        let passages = nearDuplicatePassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: referenceMoments(for: passages))

        let mistakenContinuation = Array(passages.1[8...12])
        let recovery = Array(passages.0[13...17])
        let positions = consume(
            Array(passages.0.prefix(8)) + mistakenContinuation + recovery,
            with: follower,
            startingAt: 1_000
        )

        #expect(positions.filter(\.didJump).count == 0)
        #expect(follower.lastPosition?.beat ?? 0 < 20)
    }

    /// Verifies that an ambiguous later phrase cannot override the established local passage.
    @Test("does not jump to a similar later passage after ambiguous history")
    func doesNotJumpToSimilarLaterPassageAfterAmbiguousHistory() async {
        let passages = similarPassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: referenceMoments(for: passages))

        _ = consume(Array(passages.0.prefix(8)), with: follower, startingAt: 1_000)
        let positions = consume(Array(passages.1.suffix(5)), with: follower, startingAt: 100_000)

        #expect(!positions.contains { $0.didJump })
        #expect(positions.last?.beat == 19)
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

    /// Creates two 20-chord, piano-style passages that share a harmonic language but diverge at the cadence.
    private func similarPassages() -> ([[UInt8]], [[UInt8]]) {
        let firstPassage: [[UInt8]] = [
            [48, 55, 60, 64], [47, 55, 59, 62], [45, 52, 55, 60], [43, 52, 55, 59],
            [41, 48, 53, 57], [40, 48, 52, 55], [45, 52, 57, 60], [43, 50, 55, 59],
            [41, 48, 53, 57], [43, 50, 55, 59], [45, 52, 57, 60], [47, 54, 59, 62],
            [48, 55, 60, 64], [52, 55, 60, 64], [50, 57, 62, 65], [43, 50, 55, 59],
            [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59], [48, 55, 60, 64]
        ]
        let secondPassage: [[UInt8]] = [
            [48, 55, 60, 64], [47, 55, 59, 62], [45, 52, 55, 60], [43, 52, 55, 59],
            [41, 48, 53, 57], [40, 48, 52, 55], [45, 52, 57, 60], [43, 50, 55, 59],
            [41, 48, 53, 57], [43, 50, 55, 59], [45, 52, 57, 60], [47, 54, 59, 62],
            [48, 55, 60, 64], [52, 55, 60, 64], [50, 57, 62, 65], [45, 52, 57, 60],
            [41, 48, 53, 57], [45, 52, 57, 60], [43, 50, 55, 59], [48, 55, 60, 64]
        ]
        return (firstPassage, secondPassage)
    }

    /// Creates passages that differ only in their upper voice, as when a performer makes small voicing mistakes.
    private func nearDuplicatePassages() -> ([[UInt8]], [[UInt8]]) {
        let firstPassage = similarPassages().0
        var secondPassage = firstPassage
        secondPassage[8] = [41, 48, 53, 60]
        secondPassage[9] = [43, 50, 55, 60]
        secondPassage[10] = [45, 52, 57, 62]
        secondPassage[11] = [47, 54, 59, 64]
        secondPassage[12] = [48, 55, 60, 65]
        secondPassage[13] = [52, 55, 60, 65]
        secondPassage[14] = [50, 57, 62, 67]
        secondPassage[15] = [43, 50, 55, 60]
        secondPassage[16] = [45, 52, 57, 62]
        secondPassage[17] = [41, 48, 53, 60]
        return (firstPassage, secondPassage)
    }

    /// Converts the supplied passages into consecutive score moments.
    private func referenceMoments(for passages: ([[UInt8]], [[UInt8]])) -> [ScoreFollower.ReferenceMoment] {
        (passages.0 + passages.1).enumerated().map { index, pitches in
            .init(beat: Double(index), pitches: Set(pitches))
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


    /// Feeds chords in score order from a specified timestamp for deterministic jump testing.
    private func consume(
        _ chords: [[UInt8]],
        with follower: ScoreFollower,
        startingAt initialTimestamp: MIDITimeStamp
    ) -> [ScoreFollower.Position] {
        var timestamp = initialTimestamp
        var positions: [ScoreFollower.Position] = []

        for chord in chords {
            for pitch in chord {
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


@Suite("Score follower jump stability supplemental")
struct ScoreFollowerJumpStabilitySupplementalTests {

    /// Verifies that one-note variations cannot confirm a move to a similar later passage.
    @Test("does not jump for one-note variations in a similar passage")
    func doesNotJumpForOneNoteVariationsInSimilarPassage() async {
        let passages = nearDuplicatePassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: jumpReferenceMoments(for: passages))

        let positions = consumeJumpChords(Array(passages.0.prefix(8)) + Array(passages.1[8...12]), with: follower)

        #expect(positions.filter(\.didJump).isEmpty)
        #expect(follower.lastPosition?.beat ?? 0 < 20)
    }

    /// Verifies that correcting near-duplicate mistakes cannot cause a false jump back.
    @Test("does not bounce after recovering from near-duplicate mistakes")
    func doesNotBounceAfterRecoveringFromNearDuplicateMistakes() async {
        let passages = nearDuplicatePassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: jumpReferenceMoments(for: passages))

        let positions = consumeJumpChords(
            Array(passages.0.prefix(8)) + Array(passages.1[8...12]) + Array(passages.0[13...17]),
            with: follower
        )

        #expect(positions.filter(\.didJump).isEmpty)
        #expect(follower.lastPosition?.beat ?? 0 < 20)
    }

    /// Verifies that three complete, strongly different remote chords remain insufficient confirmation.
    @Test("does not jump for three distinct remote chords")
    func doesNotJumpForThreeDistinctRemoteChords() async {
        let passages = stronglyDistinctPassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: jumpReferenceMoments(for: passages))

        let positions = consumeJumpChords(Array(passages.0.prefix(8)) + Array(passages.1[8...10]), with: follower)

        #expect(positions.filter(\.didJump).isEmpty)
        #expect(follower.lastPosition?.beat ?? 0 < 20)
    }

    /// Verifies that four complete, strongly different remote chords permit exactly one intentional jump.
    @Test("jumps after four distinct remote chords")
    func jumpsAfterFourDistinctRemoteChords() async {
        let passages = stronglyDistinctPassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: jumpReferenceMoments(for: passages))

        let positions = consumeJumpChords(Array(passages.0.prefix(8)) + Array(passages.1[8...12]), with: follower)

        #expect(positions.filter(\.didJump).count == 1)
        #expect(follower.lastPosition?.beat == 32)
    }

    /// Creates 20-chord passages with an ambiguous single-note upper-voice variation.
    private func nearDuplicatePassages() -> ([[UInt8]], [[UInt8]]) {
        let firstPassage = jumpBasePassage()
        var secondPassage = firstPassage
        secondPassage[8] = [41, 48, 53, 60]
        secondPassage[9] = [43, 50, 55, 60]
        secondPassage[10] = [45, 52, 57, 62]
        secondPassage[11] = [47, 54, 59, 64]
        secondPassage[12] = [48, 55, 60, 65]
        return (firstPassage, secondPassage)
    }

    /// Creates 20-chord passages with a clearly distinct second cadence.
    private func stronglyDistinctPassages() -> ([[UInt8]], [[UInt8]]) {
        let firstPassage = jumpBasePassage()
        var secondPassage = firstPassage
        secondPassage[8] = [20, 24, 27, 31]
        secondPassage[9] = [21, 25, 28, 32]
        secondPassage[10] = [22, 26, 29, 33]
        secondPassage[11] = [23, 27, 30, 34]
        secondPassage[12] = [24, 28, 31, 35]
        return (firstPassage, secondPassage)
    }
}


/// Creates a realistic 20-chord piano passage.
private func jumpBasePassage() -> [[UInt8]] {
    [
        [48, 55, 60, 64], [47, 55, 59, 62], [45, 52, 55, 60], [43, 52, 55, 59],
        [41, 48, 53, 57], [40, 48, 52, 55], [45, 52, 57, 60], [43, 50, 55, 59],
        [41, 48, 53, 57], [43, 50, 55, 59], [45, 52, 57, 60], [47, 54, 59, 62],
        [48, 55, 60, 64], [52, 55, 60, 64], [50, 57, 62, 65], [43, 50, 55, 59],
        [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59], [48, 55, 60, 64]
    ]
}

/// Converts two passages into consecutive score moments.
private func jumpReferenceMoments(for passages: ([[UInt8]], [[UInt8]])) -> [ScoreFollower.ReferenceMoment] {
    (passages.0 + passages.1).enumerated().map { index, pitches in
        .init(beat: Double(index), pitches: Set(pitches))
    }
}

/// Feeds chords in score order and records every inferred position.
private func consumeJumpChords(_ chords: [[UInt8]], with follower: ScoreFollower) -> [ScoreFollower.Position] {
    var timestamp: MIDITimeStamp = 1_000
    var positions: [ScoreFollower.Position] = []

    for chord in chords {
        for pitch in chord {
            if let position = follower.consume(noteOn: pitch, timestamp: timestamp) {
                positions.append(position)
            }
            timestamp += 1_000
        }
    }

    return positions
}
