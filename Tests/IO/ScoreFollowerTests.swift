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
    func followsMelody() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62, 64]))

        let positions = consume([60, 62, 64], with: follower)

        #expect(positions.map(\.beat) == [0, 1, 2])
        #expect(positions.allSatisfy { !$0.didJump })
    }

    @Test("recovers after a wrong note")
    func recoversAfterWrongNote() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62, 64]))

        _ = consume(60, with: follower, at: 1_000)
        _ = consume(61, with: follower, at: 2_000)
        _ = consume(62, with: follower, at: 3_000)
        let position = consume(64, with: follower, at: 4_000)

        #expect(position?.beat == 2)
    }

    @Test("advances across missing reference notes")
    func handlesMissingNotes() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62, 64, 65]))

        _ = consume(60, with: follower, at: 1_000)
        let position = consume(65, with: follower, at: 4_000)

        #expect(position?.beat == 3)
    }

    @Test("retains its position for extra performed notes")
    func handlesExtraNotes() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62]))

        _ = consume(60, with: follower, at: 1_000)
        let extraPosition = consume(61, with: follower, at: 2_000)
        let recoveredPosition = consume(62, with: follower, at: 3_000)

        #expect(extraPosition?.beat == 0)
        #expect(recoveredPosition?.beat == 1)
    }

    /// Ensures local alignment continues after a performed phrase omits a score note.
    @Test("matches later notes after a skipped score note")
    func toleratesSkippedNote() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62, 64, 65, 67]))

        let positions = consume([60, 64, 65, 67], with: follower)

        #expect(positions.last?.beat == 4)
    }

    /// Ensures an extra performed pitch does not prevent later score alignment.
    @Test("matches later notes after an extra performed note")
    func toleratesExtraNote() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62, 64, 65, 67]))

        let positions = consume([60, 62, 61, 64, 65, 67], with: follower)

        #expect(positions.last?.beat == 4)
    }

    /// Ensures one incorrect performed pitch can be treated as a substitution.
    @Test("matches later notes after an incorrect performed note")
    func toleratesIncorrectNote() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62, 64, 65, 67]))

        let positions = consume([60, 62, 63, 65, 67], with: follower)

        #expect(positions.last?.beat == 4)
    }

    @Test("matches chord pitches independent of arrival order")
    func matchesChordInAnyOrder() async {
        let follower = ScoreFollower()
        await follower.update(reference: [
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
    func keepsSlowChordOpen() async {
        let follower = ScoreFollower()
        await follower.update(reference: [
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
    func closesIncompleteChord() async {
        let follower = ScoreFollower()
        await follower.update(reference: [
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
    func handlesPartialChord() async {
        let follower = ScoreFollower()
        await follower.update(reference: [
            .init(beat: 0, pitch: 60),
            .init(beat: 0, pitch: 64),
            .init(beat: 1, pitch: 67)
        ])

        _ = consume(60, with: follower, at: 1_000)
        let position = consume(67, with: follower, at: 2_000)

        #expect(position?.beat == 1)
    }

    @Test("repeated notes do not produce a false jump")
    func repeatedNotesDoNotJump() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 60, 60, 60, 60, 60]))

        let positions = consume([60, 60, 60, 60, 60, 60], with: follower)

        #expect(positions.allSatisfy { !$0.didJump })
        #expect(positions.last?.beat == 5)
    }

    /// Ensures a sustained run of ambiguous repeated pitches continues to the end of a long score.
    @Test("continues through a long repeated-pitch passage")
    func followsLongRepeatedPitchPassage() async {
        let pitches = Array(repeating: UInt8(60), count: 128)
        let follower = ScoreFollower()
        await follower.update(reference: reference(pitches))

        let positions = consume(pitches, with: follower)

        #expect(positions.last?.beat == 127)
    }

    /// Ensures ambiguous matches advance continuously instead of leaving the committed position behind.
    @Test("advances every match through a long repeated-pitch passage")
    func advancesEveryLongRepeatedPitchMatch() async {
        let pitches = Array(repeating: UInt8(60), count: 128)
        let follower = ScoreFollower()
        await follower.update(reference: reference(pitches))

        let positions = consume(pitches, with: follower)

        #expect(positions.map(\.beat) == (0..<128).map(Double.init))
    }

    /// Ensures repeated-pitch alignment remains fast enough to keep up with live MIDI input.
    @Test("processes a dense repeated-pitch passage without stalling")
    func processesDenseRepeatedPitchPassagePromptly() async {
        let pitches = Array(repeating: UInt8(60), count: 512)
        let follower = ScoreFollower()
        await follower.update(reference: reference(pitches))

        let clock = ContinuousClock()
        let start = clock.now
        let positions = consume(pitches, with: follower)
        let elapsed = start.duration(to: clock.now)

        #expect(positions.last?.beat == 511)
        #expect(elapsed < .seconds(1))
    }

    /// Ensures complete, consecutive chords remain aligned when they share pitches and arrive in varied order.
    @Test("follows a long progression of overlapping chords")
    func followsLongOverlappingChordProgression() async {
        let chords: [[UInt8]] = [
            [60, 64, 67], [62, 65, 69], [59, 62, 67], [60, 64, 67],
            [57, 60, 64], [55, 59, 62], [60, 64, 67], [62, 65, 69],
            [59, 62, 67], [60, 64, 67], [57, 60, 64], [55, 59, 62]
        ]
        let follower = ScoreFollower()
        await follower.update(
            referenceMoments: chords.enumerated().map { index, pitches in
                .init(beat: Double(index), pitches: Set(pitches))
            }
        )

        var positions: [ScoreFollower.Position] = []
        for (chordIndex, chord) in chords.enumerated() {
            for (pitchIndex, pitch) in chord.reversed().enumerated() {
                let timestamp = MIDITimeStamp(chordIndex * chord.count + pitchIndex + 1) * 1_000
                if let position = consume(pitch, with: follower, at: timestamp) {
                    positions.append(position)
                }
            }
        }

        #expect(
            positions.map(\.beat)
                == (0..<12).flatMap { Array(repeating: Double($0), count: 3) }
        )
    }

    /// Ensures score alignment handles widely spaced moments whose chord sizes vary substantially.
    @Test("follows distinct chords with varying sizes across large beat gaps")
    func followsDistinctWidelySpacedChords() async {
        let chords: [[UInt8]] = [
            [36],
            [37, 38],
            [39, 40, 41],
            [42, 43, 44, 45],
            [46, 47, 48, 49, 50],
            [51, 52, 53, 54, 55, 56],
            [57, 58, 59, 60, 61, 62, 63],
            [64, 65, 66, 67, 68, 69, 70, 71],
            [72, 73, 74, 75, 76, 77, 78, 79, 80],
            [81, 82, 83, 84, 85, 86, 87, 88, 89, 90]
        ]
        let follower = ScoreFollower()
        await follower.update(
            referenceMoments: chords.enumerated().map { index, pitches in
                .init(beat: Double(index * 8), pitches: Set(pitches))
            }
        )

        var timestamp: MIDITimeStamp = 1_000
        var positions: [ScoreFollower.Position] = []
        for chord in chords {
            for pitch in chord.reversed() {
                if let position = consume(pitch, with: follower, at: timestamp) {
                    positions.append(position)
                }
                timestamp += 1_000
            }
        }

        #expect(positions.last?.beat == 72)
    }

    /// Ensures overlapping, differently sized chords advance to every widely spaced score moment.
    @Test("follows widely spaced chords with a shared tone and varying sizes")
    func followsAmbiguousWidelySpacedChords() async {
        let chords: [[UInt8]] = [
            [60],
            [60, 61],
            [60, 61, 62],
            [60, 61, 62, 63],
            [60, 61, 62, 63, 64],
            [60, 61, 62, 63, 64, 65],
            [60, 61, 62, 63, 64, 65, 66],
            [60, 61, 62, 63, 64, 65, 66, 67],
            [60, 61, 62, 63, 64, 65, 66, 67, 68],
            [60, 61, 62, 63, 64, 65, 66, 67, 68, 69]
        ]
        let follower = ScoreFollower()
        await follower.update(
            referenceMoments: chords.enumerated().map { index, pitches in
                .init(beat: Double(index * 8), pitches: Set(pitches))
            }
        )

        var timestamp: MIDITimeStamp = 1_000
        var chordBeats: [Double] = []
        for chord in chords {
            for pitch in chord.reversed() {
                _ = consume(pitch, with: follower, at: timestamp)
                timestamp += 1_000
            }
            chordBeats.append(follower.lastPosition?.beat ?? -.infinity)
        }

        #expect(chordBeats == stride(from: 0, through: 72, by: 8).map(Double.init))
    }

    @Test("starts from a matching middle passage")
    func startsFromMiddle() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([48, 50, 70, 71, 72, 73, 74, 75]))

        let positions = consume([70, 71, 72, 73, 74, 75], with: follower)

        #expect(positions.last?.beat == 7)
    }

    @Test("jumps to a middle passage when performance begins there")
    func jumpsToMiddlePassage() async {
        let pitches = Array(48...79).map(UInt8.init)
        let follower = ScoreFollower()
        await follower.update(reference: reference(pitches))
        let middlePassage = Array(pitches[16...23])

        let positions = consume(middlePassage, with: follower)

        #expect(positions.last?.beat == 23)
        #expect(positions.contains { $0.didJump })
    }

    @Test("jumps back to the first quarter after reaching the score end")
    func jumpsBackAfterReachingEnd() async {
        let pitches = Array(48...79).map(UInt8.init)
        let follower = ScoreFollower()
        await follower.update(reference: reference(pitches))

        _ = consume(pitches, with: follower)
        let positions = consume(Array(pitches[8...15]), with: follower)

        #expect(positions.last?.beat == 15)
        #expect(positions.contains { $0.didJump })
    }


    /// Ensures a remote exact phrase can replace an established but error-prone local continuation.
    @Test("jumps to a perfect remote phrase over an imperfect local continuation")
    func prefersPerfectRemotePhrase() async {
        let prefix: [UInt8] = [40, 41, 42, 43]
        let localContinuation: [UInt8] = [60, 61, 70, 71, 72, 73, 74]
        let bridge: [UInt8] = [80, 81, 82, 83, 84, 85, 86, 87, 88, 89]
        let remoteContinuation: [UInt8] = [60, 61, 62, 63, 64, 65, 66, 67]
        let follower = ScoreFollower()
        await follower.update(
            reference: reference(prefix + localContinuation + bridge + remoteContinuation)
        )

        let positions = consume(prefix + remoteContinuation, with: follower)

        #expect(positions.last?.beat == 28)
        #expect(positions.contains { $0.didJump })
    }

    @Test("retains quiet note-ons as soft alignment evidence")
    func retainsQuietNotes() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62]))

        _ = follower.consume(noteOn: 60, velocity: 1, timestamp: 1_000)
        let position = follower.consume(noteOn: 62, velocity: 1, timestamp: 2_000)

        #expect(position?.beat == 1)
    }

    @Test("note-offs confirm a released chord without advancing")
    func noteOffsInformChordEvidence() async {
        let follower = ScoreFollower()
        await follower.update(reference: [
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
    func recognizesReleasedRepeatedPitch() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 60]))

        _ = follower.consume(noteOn: 60, timestamp: 1_000)
        follower.consume(noteOff: 60)
        let position = follower.consume(noteOn: 60, timestamp: 2_000)

        #expect(position?.beat == 1)
    }

    @Test("zero timestamps retain pitch-only alignment")
    func zeroTimestampsRetainPitchOnlyAlignment() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62, 64]))

        let positions = [60, 62, 64].compactMap {
            consume($0, with: follower, at: 0)
        }

        #expect(positions.map(\.beat) == [0, 1, 2])
    }

    /// Ensures a reset does not assume the performer has restarted from the first reference moment.
    @Test("reset waits for enough alignment evidence")
    func resetWaitsForAlignmentEvidence() async {
        let follower = ScoreFollower()
        await follower.update(reference: reference([60, 62]))

        _ = consume(60, with: follower, at: 1_000)
        follower.reset()

        #expect(follower.lastPosition == nil)
        #expect(consume(60, with: follower, at: 2_000) == nil)
        #expect(consume(62, with: follower, at: 3_000)?.beat == 1)
    }

    @Test("updates from pre-grouped reference moments")
    func updatesReferenceMoments() async {
        let follower = ScoreFollower()
        await follower.update(referenceMoments: [
            .init(beat: 0, pitches: [60, 64]),
            .init(beat: 1, pitches: [67])
        ])

        _ = consume(64, with: follower, at: 1_000)
        #expect(consume(67, with: follower, at: 2_000)?.beat == 1)

        await follower.update(referenceMoments: [.init(beat: 4, pitches: [72])])
        #expect(follower.lastPosition == nil)
        #expect(consume(72, with: follower, at: 3_000)?.beat == 4)
    }

    /// Verifies that an empty follower acquires an ambiguous phrase inside the visible score region.
    @Test("visible range directs initial alignment")
    func visibleRangeDirectsInitialAlignment() async {
        let follower = ScoreFollower()
        follower.visibleRange = 10...11
        await follower.update(reference: [
            .init(beat: 0, pitch: 60),
            .init(beat: 1, pitch: 62),
            .init(beat: 5, pitch: 70),
            .init(beat: 10, pitch: 60),
            .init(beat: 11, pitch: 62)
        ])

        let positions = consume([60, 62], with: follower)

        #expect(positions.last?.beat == 11)
    }

    /// Verifies that the visible prior cannot bypass continuity for an established alignment.
    @Test("visible range retains local continuity")
    func visibleRangeRetainsLocalContinuity() async {
        let follower = ScoreFollower()
        await follower.update(reference: [
            .init(beat: 0, pitch: 60),
            .init(beat: 1, pitch: 62),
            .init(beat: 2, pitch: 64),
            .init(beat: 10, pitch: 64)
        ])
        _ = consume([60, 62], with: follower)
        follower.visibleRange = 10...10

        let position = consume(64, with: follower, at: 3_000)

        #expect(position?.beat == 2)
        #expect(position?.didJump == false)
    }

    @Test("merges near-simultaneous pre-grouped reference moments")
    func mergesNearSimultaneousReferenceMoments() async {
        let follower = ScoreFollower()
        await follower.update(referenceMoments: [
            .init(beat: 0, pitches: [60]),
            .init(beat: 0.0000005, pitches: [64])
        ])

        #expect(Set(follower.reference) == [
            .init(beat: 0, pitch: 60),
            .init(beat: 0, pitch: 64)
        ])
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


