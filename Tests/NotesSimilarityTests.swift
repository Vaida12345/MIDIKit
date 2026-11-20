//
//  NotesSimilarityTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import MIDIKit


// MARK: - Support

private func note(_ onset: Double, _ offset: Double, _ pitch: UInt8 = 60) -> MIDINote {
    MIDINote(onset: onset, offset: offset, note: pitch, velocity: 100)
}

/// A deterministic generator, so random cases are reproducible.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Random notes, and a perturbed copy: jittered times, about 10% dropped, and some extra notes.
private func randomPair(count: Int, seed: UInt64) -> (MIDINotes, MIDINotes) {
    var generator = SplitMix64(state: seed)
    var lhs: [MIDINote] = []
    var rhs: [MIDINote] = []
    for _ in 0..<count {
        let onset = Double.random(in: 0..<Double(count) / 4, using: &generator)
        let duration = Double.random(in: 0.1..<2, using: &generator)
        let pitch = UInt8.random(in: 48...72, using: &generator)
        lhs.append(note(onset, onset + duration, pitch))

        if Double.random(in: 0..<1, using: &generator) < 0.9 {
            let shift = Double.random(in: -0.08...0.08, using: &generator)
            let stretch = Double.random(in: -0.2...0.2, using: &generator)
            rhs.append(note(onset + shift, onset + shift + duration + stretch * duration, pitch))
        }
        if Double.random(in: 0..<1, using: &generator) < 0.1 {
            let extra = Double.random(in: 0..<Double(count) / 4, using: &generator)
            rhs.append(note(extra, extra + duration, pitch))
        }
    }
    return (MIDINotes(lhs), MIDINotes(rhs))
}


// MARK: - Tests

@Suite(.timeLimit(.minutes(1)))
struct NotesSimilarityTests {

    @Test
    func identical() {
        let notes = MIDINotes([note(0, 1), note(1, 2, 62), note(2, 3, 64)])
        let similarity = notes.similarity(to: notes)

        #expect(similarity.score == 1)
        #expect(similarity.matchedCount == 3)
        #expect(similarity.unmatchedCount == 0 && similarity.otherUnmatchedCount == 0)
        #expect(similarity.onsetRMSE == 0 && similarity.offsetRMSE == 0)
    }

    @Test
    func empty() {
        let none = MIDINotes([]).similarity(to: MIDINotes([]))
        #expect(none.score == 1)
        #expect(none.matchedCount == 0)
        #expect(none.onsetRMSE == nil && none.offsetRMSE == nil)

        let oneSided = MIDINotes([note(0, 1), note(1, 2)]).similarity(to: MIDINotes([]))
        #expect(oneSided.score == 0)
        #expect(oneSided.unmatchedCount == 2 && oneSided.otherUnmatchedCount == 0)
    }

    /// A wrong pitch is a miss and an extra note.
    @Test
    func differentPitches() {
        let similarity = MIDINotes([note(0, 1, 60)]).similarity(to: MIDINotes([note(0, 1, 61)]))
        #expect(similarity.score == 0)
        #expect(similarity.unmatchedCount == 1 && similarity.otherUnmatchedCount == 1)
    }

    /// When every pair is exact or beyond the tolerances, the score is the F1 score.
    @Test
    func hardToleranceIsF1() {
        let lhs = MIDINotes([note(0, 1, 60), note(1, 2, 62), note(2, 3, 64), note(3, 4, 65)])
        let rhs = MIDINotes([note(0, 1, 60), note(1, 2, 62), note(10, 11, 64)])
        let similarity = lhs.similarity(to: rhs)

        #expect(similarity.matchedCount == 2)
        #expect(similarity.score == 2.0 * 2 / 7)
    }

    /// A pair counts `1 − (Δonset / τₒₙ)² − (Δoffset / τₒff)²`, where τₒff is 20% of the mean duration, here 0.2.
    @Test
    func quadraticWeight() throws {
        let similarity = MIDINotes([note(0, 1)]).similarity(to: MIDINotes([note(0.05, 1.05)]))

        #expect(abs(similarity.score - (1 - 0.25 - 0.0625)) < 1e-12)
        #expect(similarity.matchedCount == 1)
        #expect(abs(try #require(similarity.onsetRMSE) - 0.05) < 1e-12)
        #expect(abs(try #require(similarity.offsetRMSE) - 0.05) < 1e-12)
    }

    @Test
    func beyondTolerance() {
        // The onset is off by exactly the tolerance.
        let lateOnset = MIDINotes([note(0, 1)]).similarity(to: MIDINotes([note(0.1, 1.1)]))
        #expect(lateOnset.score == 0)
        #expect(lateOnset.matchedCount == 0)
        #expect(lateOnset.unmatchedCount == 1 && lateOnset.otherUnmatchedCount == 1)

        // The offset is off by more than 20% of the duration.
        let lateOffset = MIDINotes([note(0, 1)]).similarity(to: MIDINotes([note(0, 1.25)]))
        #expect(lateOffset.score == 0)
    }

    /// A note is paired at most once, even when two notes on the other side are close to it.
    @Test
    func noDoubleMatch() {
        let similarity = MIDINotes([note(0, 1)]).similarity(to: MIDINotes([note(0, 1), note(0.02, 1)]))

        #expect(similarity.matchedCount == 1)
        #expect(similarity.unmatchedCount == 0 && similarity.otherUnmatchedCount == 1)
        #expect(similarity.score == 2.0 / 3)
    }

    /// Pairing the closest notes first would pair 0.05 with 0.08 (weight 0.8875) and leave the others unpaired. Two pairs of weight 0.6875 count more.
    @Test
    func optimalNotGreedy() {
        let lhs = MIDINotes([note(0.05, 1.05), note(0.13, 1.13)])
        let rhs = MIDINotes([note(0, 1), note(0.08, 1.08)])
        let similarity = lhs.similarity(to: rhs)

        #expect(similarity.matchedCount == 2)
        #expect(abs(similarity.score - 2 * (0.6875 + 0.6875) / 4) < 1e-12)
    }

    /// The offset tolerance grows with the note.
    @Test
    func relativeOffsetTolerance() {
        // A 4-beat note released half a beat early: the tolerance is 20% of 3.75.
        let long = MIDINotes([note(0, 4)]).similarity(to: MIDINotes([note(0, 3.5)]))
        #expect(long.matchedCount == 1)
        #expect(abs(long.score - (1 - (0.5 / 0.75) * (0.5 / 0.75))) < 1e-12)

        // A 16th note held 0.15 beat longer: the tolerance stays at the onset tolerance, 0.1.
        let short = MIDINotes([note(0, 0.25)]).similarity(to: MIDINotes([note(0, 0.4)]))
        #expect(short.matchedCount == 0)
    }

    @Test(arguments: 0..<20 as Range<UInt64>)
    func symmetric(seed: UInt64) {
        let (lhs, rhs) = randomPair(count: 300, seed: seed)
        let forward = lhs.similarity(to: rhs)
        let backward = rhs.similarity(to: lhs)

        #expect(abs(forward.score - backward.score) < 1e-9)
        #expect(forward.matchedCount == backward.matchedCount)
        #expect(forward.unmatchedCount == backward.otherUnmatchedCount)
        #expect(forward.otherUnmatchedCount == backward.unmatchedCount)
        #expect((0...1).contains(forward.score))
    }

    @Test
    func unsortedInput() {
        let (lhs, rhs) = randomPair(count: 300, seed: 42)
        var generator = SplitMix64(state: 7)
        let shuffled = MIDINotes(lhs.contents.shuffled(using: &generator))

        #expect(shuffled.similarity(to: rhs) == lhs.similarity(to: rhs))
    }

    @Test
    func overlappingNotesOnOneKey() {
        let lhs = MIDINotes([note(0, 2), note(0.5, 1), note(0.5, 1)])
        let rhs = MIDINotes([note(0, 2), note(0.5, 1)])
        let similarity = lhs.similarity(to: rhs)

        #expect(similarity.matchedCount == 2)
        #expect(similarity.score == 4.0 / 5)
    }

    @Test
    func nonFiniteNotesAreNeverPaired() {
        let lhs = MIDINotes([note(.nan, 1), note(0, 1, 62)])
        let rhs = MIDINotes([note(.nan, 1), note(0, 1, 62)])
        let similarity = lhs.similarity(to: rhs)

        #expect(similarity.matchedCount == 1)
        #expect(similarity.score == 0.5)
    }

    @Test
    func scale() {
        let (lhs, rhs) = randomPair(count: 20_000, seed: 1)
        let clock = ContinuousClock()
        let start = clock.now
        let similarity = lhs.similarity(to: rhs)

        #expect(start.duration(to: clock.now) < .seconds(5))
        #expect(similarity.matchedCount > 10_000 && similarity.matchedCount <= min(lhs.count, rhs.count))
    }

}
