//
//  ScoreFollowerJumpStabilityTests.swift
//  MIDIKit
//
//  Created by Codex on 2026-08-15.
//

import CoreMIDI
import Testing
@testable import MIDIKit


@Suite("Score follower jump stability")
struct ScoreFollowerJumpStabilityTests {

    /// Verifies that one-note chord variations cannot confirm a jump to a near-duplicate passage.
    @Test("does not jump for one-note variations in a similar passage")
    func doesNotJumpForOneNoteVariationsInSimilarPassage() async {
        let passages = nearDuplicatePassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: referenceMoments(for: passages))

        let positions = consume(
            Array(passages.0.prefix(8)) + Array(passages.1[8...12]),
            with: follower
        )

        #expect(positions.filter(\.didJump).isEmpty)
        #expect(follower.lastPosition?.beat ?? 0 < 20)
    }

    /// Verifies that correcting near-duplicate mistakes cannot make the follower bounce back from a false jump.
    @Test("does not bounce after recovering from near-duplicate mistakes")
    func doesNotBounceAfterRecoveringFromNearDuplicateMistakes() async {
        let passages = nearDuplicatePassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: referenceMoments(for: passages))

        let positions = consume(
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
        await follower.update(referenceMoments: referenceMoments(for: passages))

        let positions = consume(
            Array(passages.0.prefix(8)) + Array(passages.1[8...10]),
            with: follower
        )

        #expect(positions.filter(\.didJump).isEmpty)
        #expect(follower.lastPosition?.beat ?? 0 < 20)
    }

    /// Verifies that a sustained, strongly different remote passage commits after four complete chords.
    @Test("jumps after four distinct remote chords")
    func jumpsAfterFourDistinctRemoteChords() async {
        let passages = stronglyDistinctPassages()
        let follower = ScoreFollower()
        await follower.update(referenceMoments: referenceMoments(for: passages))

        let positions = consume(
            Array(passages.0.prefix(8)) + Array(passages.1[8...12]),
            with: follower
        )

        #expect(positions.filter(\.didJump).count == 1)
        #expect(follower.lastPosition?.beat == 32)
    }

    /// Creates a pair of 20-chord passages differing only in the upper voice after their shared opening.
    private func nearDuplicatePassages() -> ([[UInt8]], [[UInt8]]) {
        let firstPassage = basePassage()
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

    /// Creates a pair of passages whose remote cadence differs by multiple chord tones.
    private func stronglyDistinctPassages() -> ([[UInt8]], [[UInt8]]) {
        let firstPassage = basePassage()
        var secondPassage = firstPassage
        secondPassage[8] = [20, 24, 27, 31]
        secondPassage[9] = [21, 25, 28, 32]
        secondPassage[10] = [22, 26, 29, 33]
        secondPassage[11] = [23, 27, 30, 34]
        secondPassage[12] = [24, 28, 31, 35]
        return (firstPassage, secondPassage)
    }

    /// Creates a realistic 20-chord piano passage in C major and its closely related harmonies.
    private func basePassage() -> [[UInt8]] {
        [
            [48, 55, 60, 64], [47, 55, 59, 62], [45, 52, 55, 60], [43, 52, 55, 59],
            [41, 48, 53, 57], [40, 48, 52, 55], [45, 52, 57, 60], [43, 50, 55, 59],
            [41, 48, 53, 57], [43, 50, 55, 59], [45, 52, 57, 60], [47, 54, 59, 62],
            [48, 55, 60, 64], [52, 55, 60, 64], [50, 57, 62, 65], [43, 50, 55, 59],
            [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59], [48, 55, 60, 64]
        ]
    }

    /// Converts two passages into consecutive score moments.
    private func referenceMoments(for passages: ([[UInt8]], [[UInt8]])) -> [ScoreFollower.ReferenceMoment] {
        (passages.0 + passages.1).enumerated().map { index, pitches in
            .init(beat: Double(index), pitches: Set(pitches))
        }
    }

    /// Feeds chords in score order and records every inferred position.
    private func consume(_ chords: [[UInt8]], with follower: ScoreFollower) -> [ScoreFollower.Position] {
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
}
