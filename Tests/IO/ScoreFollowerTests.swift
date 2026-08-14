//
//  ScoreFollowerTests.swift
//  MIDIKit
//
//  Created by Codex on 2026-08-14.
//
//  Summary: Swift Testing coverage for timestamp-aware pitch-level score following.
//

import CoreMIDI
import Testing
@testable import MIDIKit


@Suite("Score follower")
struct ScoreFollowerTests {

    @Test("follows a correctly performed monophonic melody")
    func followsMelody() {
        let follower = ScoreFollower(reference: reference([60, 62, 64]))

        let positions = consume([60, 62, 64], with: follower)

        #expect(positions.map(\.beat) == [0, 1, 2])
        #expect(positions.allSatisfy { !$0.didJump })
    }

    @Test("recovers after a wrong note")
    func recoversAfterWrongNote() {
        let follower = ScoreFollower(reference: reference([60, 62, 64]))

        _ = consume(60, with: follower, at: 1_000)
        _ = consume(61, with: follower, at: 2_000)
        _ = consume(62, with: follower, at: 3_000)
        let position = consume(64, with: follower, at: 4_000)

        #expect(position?.beat == 2)
    }

    @Test("advances across missing reference notes")
    func handlesMissingNotes() {
        let follower = ScoreFollower(reference: reference([60, 62, 64, 65]))

        _ = consume(60, with: follower, at: 1_000)
        let position = consume(65, with: follower, at: 4_000)

        #expect(position?.beat == 3)
    }

    @Test("retains its position for extra performed notes")
    func handlesExtraNotes() {
        let follower = ScoreFollower(reference: reference([60, 62]))

        _ = consume(60, with: follower, at: 1_000)
        let extraPosition = consume(61, with: follower, at: 2_000)
        let recoveredPosition = consume(62, with: follower, at: 3_000)

        #expect(extraPosition?.beat == 0)
        #expect(recoveredPosition?.beat == 1)
    }

    @Test("matches chord pitches independent of arrival order")
    func matchesChordInAnyOrder() {
        let follower = ScoreFollower(reference: [
            .init(beat: 0, pitch: 60),
            .init(beat: 0, pitch: 64),
            .init(beat: 0, pitch: 67),
            .init(beat: 1, pitch: 72)
        ])

        _ = consume(67, with: follower, at: 1_000)
        _ = consume(60, with: follower, at: 2_000)
        let chordPosition = consume(64, with: follower, at: 3_000)
        let nextPosition = consume(72, with: follower, at: 4_000)

        #expect(chordPosition?.beat == 0)
        #expect(nextPosition?.beat == 1)
    }

    @Test("keeps an incomplete chord open across a slow roll")
    func keepsSlowChordOpen() {
        let follower = ScoreFollower(reference: [
            .init(beat: 0, pitch: 60),
            .init(beat: 0, pitch: 64),
            .init(beat: 0, pitch: 67),
            .init(beat: 1, pitch: 72)
        ])

        _ = consume(60, with: follower, at: 1_000)
        _ = consume(64, with: follower, at: 10_000)
        let chordPosition = consume(67, with: follower, at: 20_000)
        let nextPosition = consume(72, with: follower, at: 30_000)

        #expect(chordPosition?.beat == 0)
        #expect(nextPosition?.beat == 1)
    }

    @Test("closes an incomplete chord when a later score moment begins")
    func closesIncompleteChord() {
        let follower = ScoreFollower(reference: [
            .init(beat: 0, pitch: 60),
            .init(beat: 0, pitch: 64),
            .init(beat: 0, pitch: 67),
            .init(beat: 1, pitch: 72)
        ])

        _ = consume(60, with: follower, at: 1_000)
        let position = consume(72, with: follower, at: 20_000)

        #expect(position?.beat == 1)
    }

    @Test("allows a partial chord before continuing")
    func handlesPartialChord() {
        let follower = ScoreFollower(reference: [
            .init(beat: 0, pitch: 60),
            .init(beat: 0, pitch: 64),
            .init(beat: 1, pitch: 67)
        ])

        _ = consume(60, with: follower, at: 1_000)
        let position = consume(67, with: follower, at: 2_000)

        #expect(position?.beat == 1)
    }

    @Test("repeated notes do not produce a false jump")
    func repeatedNotesDoNotJump() {
        let follower = ScoreFollower(reference: reference([60, 60, 60, 60, 60, 60]))

        let positions = consume([60, 60, 60, 60, 60, 60], with: follower)

        #expect(positions.allSatisfy { !$0.didJump })
        #expect(positions.last?.beat == 5)
    }

    @Test("starts from a matching middle passage")
    func startsFromMiddle() {
        let follower = ScoreFollower(reference: reference([48, 50, 70, 71, 72, 73, 74, 75]))

        let positions = consume([70, 71, 72, 73, 74, 75], with: follower)

        #expect(positions.last?.beat == 7)
    }

    @Test("jumps to a middle passage when performance begins there")
    func jumpsToMiddlePassage() {
        let pitches = Array(48...79).map(UInt8.init)
        let follower = ScoreFollower(reference: reference(pitches))
        let middlePassage = Array(pitches[16...23])

        let positions = consume(middlePassage, with: follower)

        #expect(positions.last?.beat == 23)
        #expect(positions.contains { $0.didJump })
    }

    @Test("jumps back to the first quarter after reaching the score end")
    func jumpsBackAfterReachingEnd() {
        let pitches = Array(48...79).map(UInt8.init)
        let follower = ScoreFollower(reference: reference(pitches))

        _ = consume(pitches, with: follower)
        let positions = consume(Array(pitches[8...15]), with: follower)

        #expect(positions.last?.beat == 15)
        #expect(positions.contains { $0.didJump })
    }

    @Test("retains quiet note-ons as soft alignment evidence")
    func retainsQuietNotes() {
        let follower = ScoreFollower(reference: reference([60, 62]))

        _ = follower.consume(noteOn: 60, velocity: 1, timestamp: 1_000)
        let position = follower.consume(noteOn: 62, velocity: 1, timestamp: 2_000)

        #expect(position?.beat == 1)
    }

    @Test("note-offs confirm a released chord without advancing")
    func noteOffsInformChordEvidence() {
        let follower = ScoreFollower(reference: [
            .init(beat: 0, pitch: 60),
            .init(beat: 0, pitch: 64),
            .init(beat: 1, pitch: 67)
        ])

        _ = follower.consume(noteOn: 60, timestamp: 1_000)
        follower.consume(noteOff: 60)
        #expect(follower.lastPosition?.beat == 0)

        _ = follower.consume(noteOn: 64, timestamp: 2_000)
        follower.consume(noteOff: 64)
        let position = follower.consume(noteOn: 67, timestamp: 3_000)

        #expect(position?.beat == 1)
    }

    @Test("a released repeated pitch is treated as a re-articulation")
    func recognizesReleasedRepeatedPitch() {
        let follower = ScoreFollower(reference: reference([60, 60]))

        _ = follower.consume(noteOn: 60, timestamp: 1_000)
        follower.consume(noteOff: 60)
        let position = follower.consume(noteOn: 60, timestamp: 2_000)

        #expect(position?.beat == 1)
    }

    @Test("zero timestamps retain pitch-only alignment")
    func zeroTimestampsRetainPitchOnlyAlignment() {
        let follower = ScoreFollower(reference: reference([60, 62, 64]))

        let positions = [60, 62, 64].compactMap {
            consume($0, with: follower, at: 0)
        }

        #expect(positions.map(\.beat) == [0, 1, 2])
    }

    @Test("reset restores the initial state")
    func resetRestoresInitialState() {
        let follower = ScoreFollower(reference: reference([60, 62]))

        _ = consume(60, with: follower, at: 1_000)
        follower.reset()

        #expect(follower.lastPosition == nil)
        #expect(consume(62, with: follower, at: 2_000)?.beat == 1)
    }

    private func consume(
        _ pitch: UInt8,
        with follower: ScoreFollower,
        at timestamp: MIDITimeStamp
    ) -> ScoreFollower.Position? {
        follower.consume(noteOn: pitch, timestamp: timestamp)
    }

    private func consume(
        _ pitches: [UInt8],
        with follower: ScoreFollower
    ) -> [ScoreFollower.Position] {
        pitches.enumerated().compactMap { index, pitch in
            consume(pitch, with: follower, at: MIDITimeStamp(index + 1) * 1_000)
        }
    }

    private func reference(_ pitches: [UInt8]) -> [ScoreFollower.ReferenceNote] {
        pitches.enumerated().map { index, pitch in
            .init(beat: Double(index), pitch: pitch)
        }
    }
}
