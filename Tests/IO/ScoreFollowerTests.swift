//
//  ScoreFollowerTests.swift
//  MIDIKit
//
//  Created by Codex on 2026-08-14.
//
//  Summary: Swift Testing coverage for pitch-level score-following alignment.
//

import Testing
@testable import MIDIKit


@Suite("Score follower")
struct ScoreFollowerTests {

    @Test("follows a correctly performed monophonic melody")
    func followsMelody() {
        let follower = ScoreFollower(reference: reference([60, 62, 64]))

        let positions = [60, 62, 64].compactMap { follower.consume(noteOn: $0) }

        #expect(positions.map(\.beat) == [0, 1, 2])
        #expect(positions.allSatisfy { !$0.didJump })
    }

    @Test("recovers after a wrong note")
    func recoversAfterWrongNote() {
        let follower = ScoreFollower(reference: reference([60, 62, 64]))

        _ = follower.consume(noteOn: 60)
        _ = follower.consume(noteOn: 61)
        _ = follower.consume(noteOn: 62)
        let position = follower.consume(noteOn: 64)

        #expect(position?.beat == 2)
    }

    @Test("advances across missing reference notes")
    func handlesMissingNotes() {
        let follower = ScoreFollower(reference: reference([60, 62, 64, 65]))

        _ = follower.consume(noteOn: 60)
        let position = follower.consume(noteOn: 65)

        #expect(position?.beat == 3)
    }

    @Test("retains its position for extra performed notes")
    func handlesExtraNotes() {
        let follower = ScoreFollower(reference: reference([60, 62]))

        _ = follower.consume(noteOn: 60)
        let extraPosition = follower.consume(noteOn: 61)
        let recoveredPosition = follower.consume(noteOn: 62)

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

        _ = follower.consume(noteOn: 67)
        _ = follower.consume(noteOn: 60)
        let chordPosition = follower.consume(noteOn: 64)
        let nextPosition = follower.consume(noteOn: 72)

        #expect(chordPosition?.beat == 0)
        #expect(nextPosition?.beat == 1)
    }

    @Test("allows a partial chord before continuing")
    func handlesPartialChord() {
        let follower = ScoreFollower(reference: [
            .init(beat: 0, pitch: 60),
            .init(beat: 0, pitch: 64),
            .init(beat: 1, pitch: 67)
        ])

        _ = follower.consume(noteOn: 60)
        let position = follower.consume(noteOn: 67)

        #expect(position?.beat == 1)
    }

    @Test("repeated notes do not produce a false jump")
    func repeatedNotesDoNotJump() {
        let follower = ScoreFollower(reference: reference([60, 60, 60, 60, 60, 60]))

        let positions = [60, 60, 60, 60, 60, 60].compactMap { follower.consume(noteOn: $0) }

        #expect(positions.allSatisfy { !$0.didJump })
        #expect(positions.last?.beat == 5)
    }

    @Test("starts from a matching middle passage")
    func startsFromMiddle() {
        let follower = ScoreFollower(reference: reference([48, 50, 70, 71, 72, 73, 74, 75]))

        let positions = [70, 71, 72, 73, 74, 75].compactMap { follower.consume(noteOn: $0) }

        #expect(positions.last?.beat == 7)
    }

    @Test("returns no position for an empty reference")
    func handlesEmptyReference() {
        let follower = ScoreFollower(reference: [])

        #expect(follower.consume(noteOn: 60) == nil)
        #expect(follower.lastPosition == nil)
    }

    @Test("reset restores the initial state")
    func resetRestoresInitialState() {
        let follower = ScoreFollower(reference: reference([60, 62]))

        _ = follower.consume(noteOn: 60)
        follower.reset()

        #expect(follower.lastPosition == nil)
        #expect(follower.consume(noteOn: 62)?.beat == 1)
    }

    private func reference(_ pitches: [UInt8]) -> [ScoreFollower.ReferenceNote] {
        pitches.enumerated().map { index, pitch in
            .init(beat: Double(index), pitch: pitch)
        }
    }
}
