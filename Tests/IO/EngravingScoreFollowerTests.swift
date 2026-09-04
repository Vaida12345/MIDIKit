//
//  EngravingScoreFollowerTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-09-03.
//

import CoreAudio
import CoreMIDI
import Testing
@testable import MIDIKit


@Suite("Engraving score follower")
struct EngravingScoreFollowerTests {

    @Test("the latest post-reset viewport directs acquisition")
    func latestViewportDirectsAcquisition() async throws {
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 1, pitches: [62]),
                Self.rightMoment(beat: 4, pitches: [70]),
                Self.rightMoment(beat: 5, pitches: [71]),
                Self.rightMoment(beat: 8, pitches: [60]),
                Self.rightMoment(beat: 9, pitches: [62])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)

        follower.visibleRange = 0...4
        #expect(follower.consume(noteOn: 127, timestamp: 500) == nil)
        follower.visibleRange = 4...8
        follower.visibleRange = 8...12

        _ = Self.perform(pitch: 60, timestamp: 1_000, with: follower)
        let update = Self.perform(pitch: 62, timestamp: 2_000, with: follower)

        #expect(update?.beat == 9)
        #expect(update?.measureIndex == 2)
    }

    @Test("corroborated musical evidence can override the initial viewport hint")
    func musicalEvidenceOverridesViewportHint() async throws {
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 1, pitches: [61]),
                Self.rightMoment(beat: 4, pitches: [70]),
                Self.rightMoment(beat: 5, pitches: [71]),
                Self.rightMoment(beat: 8, pitches: [60]),
                Self.rightMoment(beat: 9, pitches: [90]),
                Self.rightMoment(beat: 10, pitches: [91])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = Self.perform(pitch: 60, timestamp: 1_000, with: follower)
        let uncorroborated = Self.perform(pitch: 90, timestamp: 2_000, with: follower)
        let update = Self.perform(pitch: 91, timestamp: 3_000, with: follower)

        #expect(uncorroborated == nil)
        #expect(update?.beat == 10)
        #expect(update?.displayBeat == 10)
        #expect(update?.measureIndex == 2)
        #expect(update?.didReframe == true)
        #expect(update?.viewport == .jump(toLine: 2))
    }

    @Test("an ambiguous complete chord does not publish an acquisition")
    func ambiguousCompleteChordRemainsPrivate() async throws {
        let chord: [UInt8] = [48, 60, 64, 67]
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: [
                Self.bothHandMoment(beat: 0, pitches: chord),
                Self.bothHandMoment(beat: 8, pitches: chord)
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)

        var update: EngravingScoreFollower.Update?
        for (offset, pitch) in chord.enumerated() {
            update = follower.consume(
                noteOn: pitch,
                timestamp: MIDITimeStamp(offset + 1) * 1_000
            )
        }

        #expect(update == nil)
        #expect(follower.lastUpdate == nil)
    }

    @Test("follows right-hand-only practice automatically")
    func followsRightHandOnly() async throws {
        let reference = try Self.twoHandReference()
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 8...16

        var timestamp: MIDITimeStamp = 1_000
        var update: EngravingScoreFollower.Update?
        for moment in reference.moments[8...13] {
            for note in moment.notes where note.hand == .right {
                update = Self.perform(pitch: note.pitch, timestamp: timestamp, with: follower)
                timestamp += 1_000
            }
        }

        #expect(update?.beat == 13)
        #expect(update?.activeHands == .right)
        #expect(update?.didReframe == false)
    }

    @Test("the inactive hand cannot advance a one-hand interpretation")
    func inactiveHandCannotAdvanceOneHandInterpretation() async throws {
        let left: [UInt8] = [48, 50, 52, 53, 55, 60]
        let right: [UInt8] = [72, 74, 76, 77, 60, 79]
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4)
            ],
            lines: [.init(index: 0, beatRange: 0...8, measureRange: 0...1)],
            moments: left.indices.map { index in
                EngravingReference.Moment(
                    beat: Double(index),
                    notes: [
                        .init(pitch: left[index], duration: 1, hand: .left),
                        .init(pitch: right[index], duration: 1, hand: .right)
                    ]
                )
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...8

        for (index, pitch) in left.prefix(5).enumerated() {
            _ = Self.perform(
                pitch: pitch,
                timestamp: MIDITimeStamp(index + 1) * 1_000,
                with: follower
            )
        }

        // Pitch 60 belongs to the inactive right hand at beat 4 and to the left hand at beat 5.
        let update = Self.perform(pitch: 60, timestamp: 6_000, with: follower)
        #expect(update?.beat == 4)
        #expect(update?.activeHands == .left)
    }

    @Test("infers both hands independently of chord note order")
    func infersBothHands() async throws {
        let reference = try Self.twoHandReference()
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...8

        var timestamp: MIDITimeStamp = 1_000
        var update: EngravingScoreFollower.Update?
        for moment in reference.moments.prefix(5) {
            // Deliberately deliver the complete left hand before the right hand.
            for hand in [EngravingReference.Hand.left, .right] {
                for note in moment.notes where note.hand == hand {
                    update = Self.perform(pitch: note.pitch, timestamp: timestamp, with: follower)
                    timestamp += 1_000
                }
            }
        }

        #expect(update?.beat == 4)
        #expect(update?.activeHands == .both)
    }

    @Test("a confirmed visible replay moves beat while presentation waits")
    func visibleReplayKeepsPresentationStable() async throws {
        let pitches: [UInt8] = [60, 61, 62, 63, 64, 65, 66, 67, 68]
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 10, beatRange: 0...4, measureRange: 0...0),
                .init(index: 20, beatRange: 4...8, measureRange: 1...1),
                .init(index: 30, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...8

        var timestamp: MIDITimeStamp = 1_000
        for index in 0...7 {
            _ = Self.perform(pitch: pitches[index], timestamp: timestamp, with: follower)
            timestamp += 1_000
        }

        let firstReplayGesture = Self.perform(
            pitch: pitches[1],
            timestamp: timestamp,
            with: follower
        )
        timestamp += 1_000
        let secondReplayGesture = Self.perform(
            pitch: pitches[2],
            timestamp: timestamp,
            with: follower
        )
        timestamp += 1_000
        let confirmedReplay = Self.perform(
            pitch: pitches[3],
            timestamp: timestamp,
            with: follower
        )
        timestamp += 1_000

        #expect(firstReplayGesture?.beat == 7)
        #expect(firstReplayGesture?.displayBeat == 7)
        #expect(secondReplayGesture?.beat == 7)
        #expect(secondReplayGesture?.displayBeat == 7)
        #expect(confirmedReplay?.beat == 3)
        #expect(confirmedReplay?.displayBeat == 7)
        #expect(confirmedReplay?.viewport == .unchanged)
        #expect(confirmedReplay?.didReframe == false)

        var caughtUp: EngravingScoreFollower.Update?
        for index in 4...7 {
            caughtUp = Self.perform(
                pitch: pitches[index],
                timestamp: timestamp,
                with: follower
            )
            timestamp += 1_000
            #expect(caughtUp?.displayBeat == 7)
            #expect(caughtUp?.viewport == .unchanged)
        }
        let movedPastFrontier = Self.perform(
            pitch: pitches[8],
            timestamp: timestamp,
            with: follower
        )

        #expect(caughtUp?.beat == 7)
        #expect(movedPastFrontier?.beat == 8)
        #expect(movedPastFrontier?.displayBeat == 8)
        #expect(movedPastFrontier?.viewport == .unchanged)
    }

    @Test("one block chord cannot consume its successor")
    func blockChordDoesNotConsumeSuccessor() async throws {
        let first: [UInt8] = [48, 55, 60, 64, 67, 72]
        let second: [UInt8] = [48, 55, 60, 65, 69, 72]
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [
                Self.bothHandMoment(beat: 0, pitches: first),
                Self.bothHandMoment(beat: 1, pitches: second)
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        var timestamp: MIDITimeStamp = 1_000
        var update: EngravingScoreFollower.Update?
        for pitch in first {
            update = follower.consume(noteOn: pitch, timestamp: timestamp)
            timestamp += 1_000
        }
        #expect(update?.beat == 0)

        for pitch in first {
            follower.consume(noteOff: pitch)
        }
        for pitch in second {
            update = follower.consume(noteOn: pitch, timestamp: timestamp)
            timestamp += 1_000
        }
        #expect(update?.beat == 1)
    }

    @Test("similar forward passages never make ordinary tracking move backward")
    func similarForwardPassagesRemainMonotone() async throws {
        let pitches: [UInt8] = [60, 62, 64, 65, 60, 62, 64, 67]
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1)
            ],
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...8

        var updates: [EngravingScoreFollower.Update] = []
        for (index, pitch) in pitches.enumerated() {
            if let update = Self.perform(
                pitch: pitch,
                timestamp: MIDITimeStamp(index + 1) * 1_000,
                with: follower
            ) {
                updates.append(update)
            }
        }

        for (previous, current) in zip(updates, updates.dropFirst()) {
            #expect(current.beat >= previous.beat)
            #expect(current.displayBeat >= previous.displayBeat)
            #expect(!current.didReframe)
        }
        #expect(updates.last?.beat == 7)
    }

    @Test("unsupported input freezes the public position and viewport")
    func uncertaintyFreezesPresentation() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 7, beatRange: 0...4, measureRange: 0...0)],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 1, pitches: [62]),
                Self.rightMoment(beat: 2, pitches: [64])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = Self.perform(pitch: 60, timestamp: 1_000, with: follower)
        let beforeMistake = Self.perform(pitch: 62, timestamp: 2_000, with: follower)
        let mistake = Self.perform(pitch: 99, timestamp: 3_000, with: follower)

        #expect(mistake?.beat == beforeMistake?.beat)
        #expect(mistake?.displayBeat == beforeMistake?.displayBeat)
        #expect(mistake?.state == .uncertain)
        #expect(mistake?.viewport == .unchanged)
        #expect(mistake?.didReframe == false)
    }

    @Test("a rolled chord remains one gesture at an unusually slow speed")
    func slowRolledChordRemainsOneGesture() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [
                Self.bothHandMoment(beat: 0, pitches: [48, 55, 60, 64, 67, 72], attack: .rolled),
                Self.bothHandMoment(beat: 1, pitches: [50, 57, 62, 65, 69, 74])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        let timestamps: [MIDITimeStamp] = [1_000, 20_000, 100_000, 500_000, 2_000_000, 9_000_000]
        var update: EngravingScoreFollower.Update?
        for (pitch, timestamp) in zip([48, 55, 60, 64, 67, 72] as [UInt8], timestamps) {
            update = follower.consume(noteOn: pitch, timestamp: timestamp)
        }

        #expect(update?.beat == 0)
    }

    @Test("a jump needs a coherent post-change episode, not two passage-like errors")
    func distinguishingSequenceActivatesRemotePassage() async throws {
        let local: [UInt8] = [60, 62, 64, 65]
        let remote: [UInt8] = [72, 74, 76, 77]
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: local.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            } + remote.enumerated().map {
                Self.rightMoment(beat: Double($0.offset + 8), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        var timestamp: MIDITimeStamp = 1_000
        _ = Self.perform(pitch: local[0], timestamp: timestamp, with: follower)
        timestamp += 1_000
        _ = Self.perform(pitch: local[1], timestamp: timestamp, with: follower)
        timestamp += 1_000

        let firstProbe = Self.perform(pitch: remote[0], timestamp: timestamp, with: follower)
        timestamp += 1_000
        let secondProbe = Self.perform(pitch: remote[1], timestamp: timestamp, with: follower)
        timestamp += 1_000
        #expect(firstProbe?.didReframe == false)
        #expect(secondProbe?.didReframe == false)

        let relocation = try #require(Self.perform(
            pitch: remote[2],
            timestamp: timestamp,
            with: follower
        ))
        #expect(relocation.didReframe)
        #expect(relocation.measureIndex == 2)
    }

    @Test("a distant relocation does not wait for complete local failure")
    func distantRelocationUsesPromptSequentialEvidence() async throws {
        let pitches = (0..<40).map { UInt8(40 + $0) }
        let reference = try EngravingReference(
            measures: (0..<10).map {
                .init(index: $0, onset: Double($0 * 4), duration: 4)
            },
            lines: (0..<10).map {
                .init(
                    index: $0,
                    beatRange: Double($0 * 4)...Double(($0 + 1) * 4),
                    measureRange: $0...$0
                )
            },
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        for index in 0...1 {
            _ = Self.perform(
                pitch: pitches[index],
                timestamp: MIDITimeStamp(index + 1) * 1_000,
                with: follower
            )
        }

        var updates: [EngravingScoreFollower.Update] = []
        for index in 32..<40 {
            if let update = Self.perform(
                pitch: pitches[index],
                timestamp: MIDITimeStamp(index + 1) * 1_000,
                with: follower
            ) {
                updates.append(update)
            }
        }

        let relocationOffset = try #require(updates.firstIndex(where: { $0.didReframe }))
        #expect(relocationOffset <= 3)
        #expect(updates[relocationOffset].beat >= 32)
        #expect(updates[relocationOffset].state == .tracking)
    }

    @Test("replaying outside the viewport is committed only as a jump")
    func offscreenReplayIsAJump() async throws {
        let pitches = (0..<40).map { UInt8(40 + $0) }
        let reference = try EngravingReference(
            measures: (0..<10).map {
                .init(index: $0, onset: Double($0 * 4), duration: 4)
            },
            lines: (0..<10).map {
                .init(
                    index: 100 + $0,
                    beatRange: Double($0 * 4)...Double(($0 + 1) * 4),
                    measureRange: $0...$0
                )
            },
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 32...40

        _ = Self.perform(pitch: pitches[32], timestamp: 1_000, with: follower)
        let acquired = Self.perform(pitch: pitches[33], timestamp: 2_000, with: follower)
        #expect(acquired?.beat == 33)

        var updates: [EngravingScoreFollower.Update] = []
        for index in 0..<14 {
            if let update = Self.perform(
                pitch: pitches[index],
                timestamp: MIDITimeStamp(index + 3) * 1_000,
                with: follower
            ) {
                updates.append(update)
            }
        }

        let jumpOffset = try #require(updates.firstIndex(where: { $0.didReframe }))
        let jump = updates[jumpOffset]
        #expect(updates[..<jumpOffset].allSatisfy { $0.beat >= 33 })
        #expect(jump.beat < 32)
        #expect(jump.displayBeat == jump.beat)
        if case let .jump(toLine: lineIndex) = jump.viewport {
            #expect(lineIndex < 108)
        } else {
            Issue.record("Offscreen replay did not produce a viewport jump")
        }
    }

    @Test("the viewport does not move when the next line is already visible")
    func visibleNextLineNeedsNoViewportMovement() async throws {
        let pitches = (60..<72).map(UInt8.init)
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 100, beatRange: 0...8, measureRange: 0...1),
                .init(index: 200, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...12

        var updates: [EngravingScoreFollower.Update] = []
        for (index, pitch) in pitches.enumerated() {
            if let update = Self.perform(
                pitch: pitch,
                timestamp: MIDITimeStamp(index + 1) * 1_000,
                with: follower
            ) {
                updates.append(update)
            }
        }

        #expect(updates.allSatisfy { $0.viewport == .unchanged })
        let lineEntry = try #require(updates.first { $0.beat == 8 })
        #expect(lineEntry.viewport == .unchanged)
        let recommendations = updates.compactMap { update -> Int? in
            guard case let .advance(toLine: line) = update.viewport else { return nil }
            return line
        }
        #expect(recommendations.isEmpty)
    }

    @Test("serialized similar chords consume exactly one score gesture each")
    func serializedSimilarChordsHaveOneBoundaryEach() async throws {
        let chords: [[UInt8]] = [
            [48, 55, 60, 64, 67, 72],
            [48, 55, 60, 65, 69, 72],
            [48, 55, 60, 64, 67, 72],
            [47, 55, 59, 65, 67, 71]
        ]
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: chords.enumerated().map {
                Self.bothHandMoment(beat: Double($0.offset), pitches: $0.element)
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        var timestamp: MIDITimeStamp = 1_000
        for (expectedIndex, chord) in chords.enumerated() {
            var updates: [EngravingScoreFollower.Update] = []
            for pitch in chord {
                if let update = follower.consume(noteOn: pitch, timestamp: timestamp) {
                    updates.append(update)
                }
                timestamp += 1_000
            }
            #expect(updates.allSatisfy { $0.beat <= Double(expectedIndex) })
            if expectedIndex == 0 {
                // The first chord occurs again later, so it must not publish an arbitrary
                // acquisition before the following gesture supplies ordered context.
                #expect(updates.isEmpty)
            } else {
                #expect(updates.last?.beat == Double(expectedIndex))
            }
            for pitch in chord { follower.consume(noteOff: pitch) }
        }
    }

    @Test("a remote passage wins even when every gesture shares local tones")
    func sharedToneJumpUsesExclusiveAnchors() async throws {
        let local: [[UInt8]] = [
            [48, 60, 64, 67], [50, 60, 65, 69], [52, 60, 64, 67], [53, 60, 65, 69]
        ]
        let remote: [[UInt8]] = [
            [36, 60, 63, 67], [38, 60, 62, 65], [40, 60, 64, 68], [41, 60, 65, 70]
        ]
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: local.enumerated().map {
                Self.bothHandMoment(beat: Double($0.offset), pitches: $0.element)
            } + remote.enumerated().map {
                Self.bothHandMoment(beat: Double($0.offset + 8), pitches: $0.element)
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        var timestamp: MIDITimeStamp = 1_000
        _ = Self.performChord(local[0], timestamp: &timestamp, with: follower)
        _ = Self.performChord(local[1], timestamp: &timestamp, with: follower)

        var remoteUpdates: [EngravingScoreFollower.Update] = []
        for chord in remote {
            for pitch in chord {
                if let update = follower.consume(noteOn: pitch, timestamp: timestamp) {
                    remoteUpdates.append(update)
                }
                timestamp += 1_000
            }
            for pitch in chord { follower.consume(noteOff: pitch) }
        }

        let jump = try #require(remoteUpdates.first(where: { $0.didReframe }))
        #expect(jump.beat >= 8)
        #expect(jump.viewport == .jump(toLine: 2))
    }

    @Test("equally plausible repeated destinations veto relocation")
    func ambiguousRemoteDestinationsPreserveContinuity() async throws {
        let local: [UInt8] = [40, 41, 42, 43]
        let repeated: [UInt8] = [60, 62, 64, 65]
        let reference = try EngravingReference(
            measures: (0..<5).map {
                .init(index: $0, onset: Double($0 * 4), duration: 4)
            },
            lines: (0..<5).map {
                .init(
                    index: $0,
                    beatRange: Double($0 * 4)...Double(($0 + 1) * 4),
                    measureRange: $0...$0
                )
            },
            moments: local.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            } + repeated.enumerated().map {
                Self.rightMoment(beat: Double($0.offset + 8), pitches: [$0.element])
            } + repeated.enumerated().map {
                Self.rightMoment(beat: Double($0.offset + 16), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        var timestamp: MIDITimeStamp = 1_000
        _ = Self.perform(pitch: local[0], timestamp: timestamp, with: follower)
        timestamp += 1_000
        _ = Self.perform(pitch: local[1], timestamp: timestamp, with: follower)
        timestamp += 1_000

        var updates: [EngravingScoreFollower.Update] = []
        for pitch in repeated {
            if let update = Self.perform(pitch: pitch, timestamp: timestamp, with: follower) {
                updates.append(update)
            }
            timestamp += 1_000
        }

        #expect(updates.allSatisfy { !$0.didReframe })
        #expect(updates.allSatisfy { $0.viewport == .unchanged })
    }

    @Test("candidate truncation cannot manufacture a unique jump destination")
    func truncatedCandidateSearchFailsClosed() async throws {
        let local: [UInt8] = [40, 41, 42, 43]
        let repeated: [UInt8] = [60, 62, 64, 65]
        let occurrenceCount = 20
        let measureCount = occurrenceCount + 2
        let reference = try EngravingReference(
            measures: (0..<measureCount).map {
                .init(index: $0, onset: Double($0 * 4), duration: 4)
            },
            lines: (0..<measureCount).map {
                .init(
                    index: $0,
                    beatRange: Double($0 * 4)...Double(($0 + 1) * 4),
                    measureRange: $0...$0
                )
            },
            moments: local.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            } + (0..<occurrenceCount).flatMap { occurrence in
                repeated.enumerated().map {
                    Self.rightMoment(
                        beat: Double(8 + occurrence * 4 + $0.offset),
                        pitches: [$0.element]
                    )
                }
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = Self.perform(pitch: local[0], timestamp: 1_000, with: follower)
        _ = Self.perform(pitch: local[1], timestamp: 2_000, with: follower)
        var updates: [EngravingScoreFollower.Update] = []
        for (offset, pitch) in repeated.enumerated() {
            if let update = Self.perform(
                pitch: pitch,
                timestamp: MIDITimeStamp(offset + 3) * 1_000,
                with: follower
            ) {
                updates.append(update)
            }
        }

        #expect(updates.allSatisfy { !$0.didReframe })
        #expect(updates.allSatisfy { $0.displayBeat < 8 })
    }

    @Test("the acquisition viewport reserves candidates without excluding score-wide evidence")
    func acquisitionViewportDoesNotBecomeAHardFilter() throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 40)],
            lines: [.init(index: 0, beatRange: 0...40, measureRange: 0...0)],
            moments: (0..<30).map {
                Self.rightMoment(beat: Double($0), pitches: [60])
            } + [Self.rightMoment(beat: 35, pitches: [60, 64, 67])]
        )
        let score = EngravingScoreFeatureIndex(reference)
        let observed = EngravingScoreFeatureIndex.pitchBit(60)
            | EngravingScoreFeatureIndex.pitchBit(64)
            | EngravingScoreFeatureIndex.pitchBit(67)

        let lookup = score.candidateLookup(
            for: observed,
            mode: .right,
            limit: 24,
            preferredRange: 0...30
        )

        #expect(lookup.indices.contains(30))
        #expect(!lookup.preferredRangeIsExhaustive)
        #expect(!lookup.isExhaustive)
    }

    @Test("presentation never promotes an unauthorized multi-line continuation to a jump")
    func presentationCannotManufactureJump() throws {
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 10, beatRange: 0...4, measureRange: 0...0),
                .init(index: 20, beatRange: 4...8, measureRange: 1...1),
                .init(index: 30, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 8, pitches: [72])
            ]
        )
        let score = EngravingScoreFeatureIndex(reference)
        var presentation = EngravingPresentationPolicy()
        _ = presentation.makeUpdate(
            from: EngravingAlignmentResult(
                gestureIndex: 0,
                confidence: 1,
                state: .tracking,
                activeHands: .right,
                movement: .held
            ),
            score: score
        )
        let update = presentation.makeUpdate(
            from: EngravingAlignmentResult(
                gestureIndex: 1,
                confidence: 1,
                state: .tracking,
                activeHands: .right,
                movement: .continuous
            ),
            score: score
        )

        #expect(update.beat == 8)
        #expect(update.displayBeat == 0)
        #expect(update.viewport == .advance(toLine: 20))
        #expect(!update.didReframe)
    }

    @Test("multi-line continuity catches presentation up one system at a time")
    func multiLinePresentationRecoveryIsStaged() throws {
        let reference = try EngravingReference(
            measures: (0..<3).map {
                .init(index: $0, onset: Double($0 * 4), duration: 4)
            },
            lines: (0..<3).map {
                .init(
                    index: 10 + $0,
                    beatRange: Double($0 * 4)...Double(($0 + 1) * 4),
                    measureRange: $0...$0
                )
            },
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 4, pitches: [64]),
                Self.rightMoment(beat: 8, pitches: [67])
            ]
        )
        let score = EngravingScoreFeatureIndex(reference)
        var presentation = EngravingPresentationPolicy()
        let prefetchedIntermediate = presentation.makeUpdate(
            from: .init(
                gestureIndex: 0,
                confidence: 1,
                state: .tracking,
                activeHands: .right,
                movement: .held
            ),
            score: score,
            visibleRange: 0...4
        )

        let firstStage = presentation.makeUpdate(
            from: .init(
                gestureIndex: 2,
                confidence: 1,
                state: .tracking,
                activeHands: .right,
                movement: .recovered
            ),
            score: score,
            visibleRange: 0...4
        )
        let secondStage = presentation.makeUpdate(
            from: .init(
                gestureIndex: 2,
                confidence: 1,
                state: .tracking,
                activeHands: .right,
                movement: .recovered
            ),
            score: score,
            visibleRange: 4...8
        )

        #expect(prefetchedIntermediate.viewport == .advance(toLine: 11))
        #expect(firstStage.displayBeat == 8)
        #expect(firstStage.viewport == .advance(toLine: 12))
        #expect(!firstStage.didReframe)
        #expect(secondStage.displayBeat == 8)
        #expect(secondStage.viewport == .unchanged)
        #expect(!secondStage.didReframe)
    }

    @Test("a committed jump must relock before another jump can be armed")
    func relocationHasEvidenceBasedRearm() async throws {
        let pitches: [UInt8] = [
            40, 41, 42, 43,
            60, 61, 62, 63,
            80, 81, 82, 83
        ]
        let beats: [Double] = [0, 1, 2, 3, 8, 9, 10, 11, 16, 17, 18, 19]
        let reference = try EngravingReference(
            measures: (0..<5).map {
                .init(index: $0, onset: Double($0 * 4), duration: 4)
            },
            lines: (0..<5).map {
                .init(
                    index: $0,
                    beatRange: Double($0 * 4)...Double(($0 + 1) * 4),
                    measureRange: $0...$0
                )
            },
            moments: zip(beats, pitches).map {
                Self.rightMoment(beat: $0.0, pitches: [$0.1])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = Self.perform(pitch: 40, timestamp: 1_000, with: follower)
        _ = Self.perform(pitch: 41, timestamp: 2_000, with: follower)
        var firstJump: EngravingScoreFollower.Update?
        for (offset, pitch) in [60, 61, 62].enumerated() {
            firstJump = Self.perform(
                pitch: UInt8(pitch),
                timestamp: MIDITimeStamp(offset + 3) * 1_000,
                with: follower
            )
        }
        #expect(firstJump?.didReframe == true)

        var immediateSecondEpisode: [EngravingScoreFollower.Update] = []
        for (offset, pitch) in [80, 81, 82, 83].enumerated() {
            if let update = Self.perform(
                pitch: UInt8(pitch),
                timestamp: MIDITimeStamp(offset + 6) * 1_000,
                with: follower
            ) {
                immediateSecondEpisode.append(update)
            }
        }
        #expect(immediateSecondEpisode.prefix(2).allSatisfy { !$0.didReframe })
        #expect(immediateSecondEpisode.contains { $0.didReframe })
    }

    @Test("passage-like errors separated by local recovery do not accumulate")
    func interruptedRemoteEvidenceStartsAnewEpisode() async throws {
        let local: [UInt8] = [60, 62, 64, 65, 67, 69]
        let remote: [UInt8] = [80, 81, 82, 83, 84, 85]
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 6),
                .init(index: 1, onset: 8, duration: 6)
            ],
            lines: [
                .init(index: 0, beatRange: 0...6, measureRange: 0...0),
                .init(index: 1, beatRange: 8...14, measureRange: 1...1)
            ],
            moments: local.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            } + remote.enumerated().map {
                Self.rightMoment(beat: Double($0.offset + 8), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...6

        var timestamp: MIDITimeStamp = 1_000
        for pitch in local.prefix(2) {
            _ = Self.perform(pitch: pitch, timestamp: timestamp, with: follower)
            timestamp += 1_000
        }

        var updates: [EngravingScoreFollower.Update] = []
        // The first local pitch can still be absorbed as an extra tone of the preceding
        // gesture. Its released re-articulation is an unambiguous physical boundary and local
        // recovery. The same pattern is repeated after the second remote-like pair.
        for pitch in [
            remote[0], remote[1],
            local[2], local[2],
            remote[2], remote[3],
            local[3], local[3]
        ] {
            if let update = Self.perform(pitch: pitch, timestamp: timestamp, with: follower) {
                updates.append(update)
            }
            timestamp += 1_000
        }

        #expect(updates.allSatisfy { !$0.didReframe })
        #expect(updates.last?.beat ?? 0 < 8)
        #expect(updates.last?.displayBeat ?? 0 < 8)
    }

    @Test("one passage-like wrong gesture remains an insertion")
    func singleRemoteLikeMistakeDoesNotRelocate() async throws {
        let local: [[UInt8]] = [
            [48, 60, 64], [50, 62, 65], [52, 64, 67], [53, 65, 69]
        ]
        let remote: [[UInt8]] = [
            [36, 60, 63], [38, 62, 65], [40, 64, 68], [41, 65, 70]
        ]
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: local.enumerated().map {
                Self.bothHandMoment(beat: Double($0.offset), pitches: $0.element)
            } + remote.enumerated().map {
                Self.bothHandMoment(beat: Double($0.offset + 8), pitches: $0.element)
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        var timestamp: MIDITimeStamp = 1_000
        _ = Self.performChord(local[0], timestamp: &timestamp, with: follower)
        _ = Self.performChord(local[1], timestamp: &timestamp, with: follower)
        let mistake = Self.performChord(remote[0], timestamp: &timestamp, with: follower)
        let recovered = Self.performChord(local[2], timestamp: &timestamp, with: follower)

        #expect(mistake?.didReframe == false)
        #expect(recovered?.didReframe == false)
        #expect(recovered?.beat == 2)
    }

    @Test("one differing anchor cannot decide an otherwise identical passage")
    func identicalPassageRequiresPostAnchorCorroboration() async throws {
        let pitches: [UInt8] = [
            60, 62, 64, 65,
            80, 81, 82, 83,
            60, 62, 64, 66, 68
        ]
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 5)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...13, measureRange: 2...2)
            ],
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = Self.perform(pitch: 60, timestamp: 1_000, with: follower)
        _ = Self.perform(pitch: 62, timestamp: 2_000, with: follower)
        _ = Self.perform(pitch: 64, timestamp: 3_000, with: follower)

        // This is the remote passage's distinguishing pitch, but can equally be a single
        // performance error at the local passage's 65.
        let ambiguousAnchor = Self.perform(pitch: 66, timestamp: 4_000, with: follower)
        let recovered = Self.perform(pitch: 65, timestamp: 5_000, with: follower)

        #expect(ambiguousAnchor?.didReframe == false)
        #expect(ambiguousAnchor?.beat == 2)
        #expect(recovered?.didReframe == false)
        #expect(recovered?.beat == 3)
    }

    @Test("decoded events preserve their MIDI input timestamps")
    func timestampedDecodedEventAPI() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 1, pitches: [62]),
                Self.rightMoment(beat: 2, pitches: [64])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = follower.consume(.noteOn(pitch: 60, velocity: 100), timestamp: 10_000)
        _ = follower.consume(.noteOff(pitch: 60), timestamp: 10_200)
        let second = follower.consume(.noteOn(pitch: 62, velocity: 100), timestamp: 20_000)
        _ = follower.consume(.noteOff(pitch: 62), timestamp: 20_200)
        let third = follower.consume(.noteOn(pitch: 64, velocity: 100), timestamp: 30_000)

        #expect(second?.beat == 1)
        #expect(third?.beat == 2)
    }

    @Test("zero and nonmonotonic timestamps fall back to pitch evidence")
    func unusableTimestampsDoNotBlockFollowing() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [60, 62, 64, 65].enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        let timestamps: [MIDITimeStamp] = [0, 1_000, 900, 4_000]
        var update: EngravingScoreFollower.Update?
        for (pitch, timestamp) in zip([60, 62, 64, 65] as [UInt8], timestamps) {
            update = follower.consume(.noteOn(pitch: pitch, velocity: 100), timestamp: timestamp)
            _ = follower.consume(.noteOff(pitch: pitch), timestamp: timestamp)
        }

        #expect(update?.beat == 3)
        #expect(update?.didReframe == false)
    }

    @Test("an unavailable timestamp contributes no same-onset timing support")
    func unavailableTimestampIsTimingNeutral() {
        let timing = PerformanceTimingModel()

        #expect(timing.sameOnsetSupport(elapsedTicks: nil, attack: .block) == 0)
        #expect(timing.sameOnsetSupport(elapsedTicks: nil, attack: .rolled) == 0)
    }

    @Test("a learned tempo cannot impose a timeout on a slow rolled chord")
    func timingNeverClosesSlowRoll() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [
                Self.rightMoment(beat: 0, pitches: [50]),
                Self.rightMoment(beat: 1, pitches: [52]),
                Self.rightMoment(beat: 2, pitches: [60, 64, 67, 72], attack: .rolled),
                Self.rightMoment(beat: 3, pitches: [62, 65, 69, 74])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = Self.perform(pitch: 50, timestamp: 1_000, with: follower)
        _ = Self.perform(pitch: 52, timestamp: 2_000, with: follower)
        let attacks: [(UInt8, MIDITimeStamp)] = [
            (60, 3_000), (64, 30_000), (67, 300_000), (72, 3_000_000)
        ]
        var update: EngravingScoreFollower.Update?
        for (pitch, timestamp) in attacks {
            update = follower.consume(noteOn: pitch, timestamp: timestamp)
        }

        #expect(update?.beat == 2)
        #expect(update?.didReframe == false)
    }

    @Test("long repetitive scores retain bounded event work")
    func longScoreStress() async throws {
        let momentCount = 1_024
        let measureCount = momentCount / 4
        let pitches: [UInt8] = (0..<momentCount).map { index in
            UInt8(36 + ((index * 17 + index / 7) % 60))
        }
        let reference = try EngravingReference(
            measures: (0..<measureCount).map {
                .init(index: $0, onset: Double($0 * 4), duration: 4)
            },
            lines: stride(from: 0, to: measureCount, by: 4).enumerated().map { line, measure in
                .init(
                    index: line,
                    beatRange: Double(measure * 4)...Double(min(measureCount, measure + 4) * 4),
                    measureRange: measure...min(measureCount - 1, measure + 3)
                )
            },
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...16

        var update: EngravingScoreFollower.Update?
        for (index, pitch) in pitches.enumerated() {
            let timestamp = MIDITimeStamp(index + 1) * 1_000
            update = follower.consume(.noteOn(pitch: pitch, velocity: 100), timestamp: timestamp)
            _ = follower.consume(.noteOff(pitch: pitch), timestamp: timestamp + 100)
        }

        #expect(update?.beat == Double(momentCount - 1))
        #expect(update?.displayBeat == Double(momentCount - 1))
    }

    @Test("a near-simultaneous extra tone stays inside the expected chord")
    func extraChordToneDoesNotSplitTheOnset() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60, 64, 67, 71]),
                Self.rightMoment(beat: 1, pitches: [62, 65, 69, 72])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        var first: EngravingScoreFollower.Update?
        for (offset, pitch) in ([60, 64, 67, 66, 71] as [UInt8]).enumerated() {
            first = follower.consume(
                noteOn: pitch,
                timestamp: MIDITimeStamp(1_000 + offset * 10)
            )
        }
        for pitch in [60, 64, 67, 66, 71] as [UInt8] { follower.consume(noteOff: pitch) }
        #expect(first?.beat == 0)

        var second: EngravingScoreFollower.Update?
        for (offset, pitch) in ([62, 65, 69, 72] as [UInt8]).enumerated() {
            second = follower.consume(
                noteOn: pitch,
                timestamp: MIDITimeStamp(2_000 + offset * 10)
            )
        }
        #expect(second?.beat == 1)
        #expect(second?.didReframe == false)
    }

    @Test("local playing resumes immediately after several mistakes")
    func mistakesDoNotRequireJumpRecovery() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 6)],
            lines: [.init(index: 0, beatRange: 0...6, measureRange: 0...0)],
            moments: [60, 62, 64, 65, 67].enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...6

        _ = Self.perform(pitch: 60, timestamp: 1_000, with: follower)
        _ = Self.perform(pitch: 62, timestamp: 2_000, with: follower)
        _ = Self.perform(pitch: 90, timestamp: 3_000, with: follower)
        _ = Self.perform(pitch: 91, timestamp: 4_000, with: follower)
        let recovered = Self.perform(pitch: 64, timestamp: 5_000, with: follower)

        #expect(recovered?.beat == 2)
        #expect(recovered?.state == .tracking)
        #expect(recovered?.didReframe == false)
    }

    @Test("lost tracking widens bounded forward repair without reframing")
    func lostTrackingUsesItsWiderRecoveryNeighborhood() async throws {
        let pitches = (60...72).map(UInt8.init)
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 16)],
            lines: [.init(index: 0, beatRange: 0...16, measureRange: 0...0)],
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...16

        _ = Self.perform(pitch: 60, timestamp: 1_000, with: follower)
        let acquired = Self.perform(pitch: 61, timestamp: 2_000, with: follower)
        #expect(acquired?.beat == 1)

        _ = Self.perform(pitch: 100, timestamp: 3_000, with: follower)
        _ = Self.perform(pitch: 101, timestamp: 4_000, with: follower)
        let lost = Self.perform(pitch: 102, timestamp: 5_000, with: follower)
        #expect(lost?.state == .lost)

        let recovered = Self.perform(pitch: 68, timestamp: 6_000, with: follower)
        #expect(recovered?.beat == 8)
        #expect(recovered?.viewport == .unchanged)
        #expect(recovered?.didReframe == false)
    }

    @Test("a long pause raises restart odds but does not block local continuation")
    func pauseStillAllowsLocalContinuation() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [60, 62, 64, 65].enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = Self.perform(pitch: 60, timestamp: 1_000, with: follower)
        _ = Self.perform(pitch: 62, timestamp: 2_000, with: follower)
        let afterPause = Self.perform(pitch: 64, timestamp: 100_000, with: follower)

        #expect(afterPause?.beat == 2)
        #expect(afterPause?.didReframe == false)
    }

    @Test("userReset reacquires from the viewport without accepting arguments")
    func userResetStartsAViewportDirectedEpoch() async throws {
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 1, pitches: [62]),
                Self.rightMoment(beat: 8, pitches: [70]),
                Self.rightMoment(beat: 9, pitches: [71])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4
        _ = Self.perform(pitch: 60, timestamp: 1_000, with: follower)
        _ = Self.perform(pitch: 62, timestamp: 2_000, with: follower)

        follower.userReset()
        follower.visibleRange = 8...12
        _ = Self.perform(pitch: 70, timestamp: 50_000, with: follower)
        let reacquired = Self.perform(pitch: 71, timestamp: 51_000, with: follower)

        #expect(reacquired?.beat == 9)
        #expect(reacquired?.didReframe == false)
    }

    @Test("velocity-zero note-on preserves release semantics and timestamp")
    func velocityZeroNoteOnIsTimestampedRelease() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 1, pitches: [60]),
                Self.rightMoment(beat: 2, pitches: [62])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = follower.consume(.noteOn(pitch: 60, velocity: 100), timestamp: 1_000)
        _ = follower.consume(.noteOn(pitch: 60, velocity: 0), timestamp: 1_500)
        let repeated = follower.consume(.noteOn(pitch: 60, velocity: 100), timestamp: 2_000)

        #expect(repeated?.beat == 1)
    }

    @Test("physical input preserves controller order and pedal timestamps")
    func physicalInputRecordsEveryControllerEventInOrder() {
        var input = PerformanceInputState()

        let first = input.noteOn(pitch: 60, velocity: 100, timestamp: 100)
        input.controlChange(control: 64, value: 127, timestamp: 200)
        let release = input.noteOff(pitch: 60, timestamp: 300)
        let second = input.noteOn(pitch: 62, velocity: 90, timestamp: 400)

        #expect(first.eventOrdinal == 0)
        #expect(input.sustainIsDown)
        #expect(input.sustainChangedAt == 200)
        #expect(release.eventOrdinal == 2)
        #expect(second.eventOrdinal == 3)
    }

    @Test("the viewport advances before an invisible next line is needed")
    func viewportAdvancesAtTheLastVisibleOnset() async throws {
        let pitches = (60..<69).map(UInt8.init)
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 100, beatRange: 0...8, measureRange: 0...1),
                .init(index: 200, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...8

        var update: EngravingScoreFollower.Update?
        for (index, pitch) in pitches.prefix(8).enumerated() {
            update = Self.perform(
                pitch: pitch,
                timestamp: MIDITimeStamp(index + 1) * 1_000,
                with: follower
            )
        }

        #expect(update?.beat == 7)
        #expect(update?.viewport == .advance(toLine: 200))
        #expect(update?.didReframe == false)
    }

    @Test("an omitted chord tone does not delay the following onset")
    func omittedChordToneRecoversOnTheNextOnset() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60, 64, 67]),
                Self.rightMoment(beat: 1, pitches: [62, 65, 69])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = follower.consume(noteOn: 60, timestamp: 1_000)
        _ = follower.consume(noteOn: 67, timestamp: 1_010)
        follower.consume(noteOff: 60)
        follower.consume(noteOff: 67)
        var update: EngravingScoreFollower.Update?
        for (offset, pitch) in ([62, 65, 69] as [UInt8]).enumerated() {
            update = follower.consume(
                noteOn: pitch,
                timestamp: MIDITimeStamp(2_000 + offset * 10)
            )
        }

        #expect(update?.beat == 1)
        #expect(update?.state == .tracking)
    }

    @Test("legato and sustain do not prevent forward following")
    func legatoUnderSustainStillAdvances() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [60, 62, 64, 65].enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4
        follower.consume(controlChange: 64, value: 127)

        var update: EngravingScoreFollower.Update?
        for (offset, pitch) in ([60, 62, 64, 65] as [UInt8]).enumerated() {
            update = follower.consume(
                noteOn: pitch,
                timestamp: MIDITimeStamp(offset + 1) * 1_000
            )
        }

        #expect(update?.beat == 3)
        #expect(update?.didReframe == false)
    }

    @Test("an initial in-score mistake does not poison acquisition")
    func initialMistakeCanBeForgottenDuringAcquisition() async throws {
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1)
            ],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 1, pitches: [62]),
                Self.rightMoment(beat: 2, pitches: [64]),
                Self.rightMoment(beat: 4, pitches: [90]),
                Self.rightMoment(beat: 5, pitches: [91])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        _ = Self.perform(pitch: 90, timestamp: 1_000, with: follower)
        _ = Self.perform(pitch: 60, timestamp: 2_000, with: follower)
        _ = Self.perform(pitch: 62, timestamp: 3_000, with: follower)
        let acquired = Self.perform(pitch: 64, timestamp: 4_000, with: follower)

        #expect(acquired?.beat == 2)
        #expect(acquired?.didReframe == false)
    }

    @Test("a visible chord remains an acquisition candidate when its notes occur alone elsewhere")
    func partialChordLookupDoesNotExcludeSupersetMoments() async throws {
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60]),
                Self.rightMoment(beat: 1, pitches: [64]),
                Self.rightMoment(beat: 2, pitches: [67]),
                Self.rightMoment(beat: 4, pitches: [60]),
                Self.rightMoment(beat: 5, pitches: [64]),
                Self.rightMoment(beat: 6, pitches: [67]),
                Self.rightMoment(beat: 8, pitches: [60, 64, 67]),
                Self.rightMoment(beat: 9, pitches: [62, 65, 69])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 8...12

        var timestamp: MIDITimeStamp = 1_000
        let acquired = Self.performChord([60, 64, 67], timestamp: &timestamp, with: follower)

        #expect(acquired?.beat == 8)
        #expect(acquired?.didReframe == false)
    }

    @Test("partial local onsets cannot outrun the committed cursor and deadlock")
    func partialOnsetsContinueWithoutAJump() async throws {
        let melody = (60..<72).map(UInt8.init)
        let reference = try EngravingReference(
            measures: [
                .init(index: 0, onset: 0, duration: 4),
                .init(index: 1, onset: 4, duration: 4),
                .init(index: 2, onset: 8, duration: 4)
            ],
            lines: [
                .init(index: 0, beatRange: 0...4, measureRange: 0...0),
                .init(index: 1, beatRange: 4...8, measureRange: 1...1),
                .init(index: 2, beatRange: 8...12, measureRange: 2...2)
            ],
            moments: melody.enumerated().map { offset, pitch in
                Self.rightMoment(
                    beat: Double(offset),
                    pitches: [pitch, UInt8(84 + offset), UInt8(96 + offset)]
                )
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...12

        var timestamp: MIDITimeStamp = 1_000_000_000
        var updates: [EngravingScoreFollower.Update] = []
        for pitch in melody {
            if let update = Self.perform(pitch: pitch, timestamp: timestamp, with: follower) {
                updates.append(update)
            }
            timestamp += 1_000_000_000
        }

        #expect(updates.last?.beat == 11)
        #expect(updates.allSatisfy { !$0.didReframe })
    }

    @Test("host-clock timing distinguishes serialized chords from detached onsets")
    func hostClockTimingUsesPhysicalUnits() async throws {
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60, 64, 67]),
                Self.rightMoment(beat: 1, pitches: [62, 65, 69])
            ]
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        let ticksPerSecond = AudioGetHostClockFrequency()
        let start: MIDITimeStamp = 10_000
        func timestamp(milliseconds: Double) -> MIDITimeStamp {
            start + MIDITimeStamp(ticksPerSecond * milliseconds / 1_000)
        }

        var first: EngravingScoreFollower.Update?
        for (pitch, milliseconds) in zip(
            [60, 64, 67] as [UInt8],
            [0.0, 3.0, 7.0]
        ) {
            first = follower.consume(noteOn: pitch, timestamp: timestamp(milliseconds: milliseconds))
        }
        for pitch in [60, 64, 67] as [UInt8] {
            follower.consume(noteOff: pitch, timestamp: timestamp(milliseconds: 180))
        }

        var second: EngravingScoreFollower.Update?
        for (pitch, milliseconds) in zip(
            [62, 65, 69] as [UInt8],
            [500.0, 503.0, 507.0]
        ) {
            second = follower.consume(noteOn: pitch, timestamp: timestamp(milliseconds: milliseconds))
        }

        #expect(first?.beat == 0)
        #expect(second?.beat == 1)
        #expect(second?.didReframe == false)
    }

    @Test("weak overall continuity does not publish tracking confidence")
    func weakOverallContinuityRemainsUncertain() async throws {
        let repeatedDestinations = (10..<42).map {
            Self.rightMoment(beat: Double($0), pitches: [71])
        }
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 48)],
            lines: [.init(index: 0, beatRange: 0...48, measureRange: 0...0)],
            moments: [
                Self.rightMoment(beat: 0, pitches: [60, 64, 67]),
                Self.rightMoment(beat: 1, pitches: [62, 65, 69]),
                Self.rightMoment(beat: 2, pitches: [71])
            ] + repeatedDestinations
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        let ticksPerSecond = AudioGetHostClockFrequency()
        func timestamp(seconds: Double) -> MIDITimeStamp {
            MIDITimeStamp(ticksPerSecond * seconds)
        }

        for pitch in [60, 64, 67] as [UInt8] {
            _ = follower.consume(noteOn: pitch, timestamp: timestamp(seconds: 1))
            follower.consume(noteOff: pitch, timestamp: timestamp(seconds: 1.1))
        }
        for pitch in [62, 65, 69] as [UInt8] {
            _ = follower.consume(noteOn: pitch, timestamp: timestamp(seconds: 2))
            follower.consume(noteOff: pitch, timestamp: timestamp(seconds: 2.1))
        }

        let update = follower.consume(noteOn: 71, timestamp: timestamp(seconds: 8))

        #expect(update?.beat == 2)
        #expect(update?.state != .tracking)
        #expect(update?.viewport == .unchanged)
    }

    private static func rightMoment(
        beat: Double,
        pitches: [UInt8],
        attack: EngravingReference.Attack = .block
    ) -> EngravingReference.Moment {
        EngravingReference.Moment(
            beat: beat,
            notes: pitches.map { .init(pitch: $0, duration: 1, hand: .right) },
            attack: attack
        )
    }

    @discardableResult
    private static func performChord(
        _ pitches: [UInt8],
        timestamp: inout MIDITimeStamp,
        with follower: EngravingScoreFollower
    ) -> EngravingScoreFollower.Update? {
        var update: EngravingScoreFollower.Update?
        for pitch in pitches {
            update = follower.consume(noteOn: pitch, timestamp: timestamp)
            timestamp += 1_000
        }
        for pitch in pitches { follower.consume(noteOff: pitch) }
        return update
    }

    private static func bothHandMoment(
        beat: Double,
        pitches: [UInt8],
        attack: EngravingReference.Attack = .block
    ) -> EngravingReference.Moment {
        let midpoint = max(1, pitches.count / 2)
        return EngravingReference.Moment(
            beat: beat,
            notes: pitches.enumerated().map { index, pitch in
                .init(
                    pitch: pitch,
                    duration: 1,
                    hand: index < midpoint ? .left : .right
                )
            },
            attack: attack
        )
    }

    private static func twoHandReference() throws -> EngravingReference {
        let left: [[UInt8]] = [
            [36, 40], [38, 41], [40, 43], [41, 45], [43, 47], [45, 48], [47, 50], [48, 52],
            [50, 53], [52, 55], [53, 57], [55, 59], [57, 60], [59, 62], [60, 64], [62, 65]
        ]
        let right: [[UInt8]] = [
            [60, 64], [62, 65], [64, 67], [65, 69], [67, 71], [69, 72], [71, 74], [72, 76],
            [74, 77], [76, 79], [77, 81], [79, 83], [81, 84], [83, 86], [84, 88], [86, 89]
        ]
        return try EngravingReference(
            measures: (0..<4).map {
                .init(index: $0, onset: Double($0 * 4), duration: 4)
            },
            lines: [
                .init(index: 0, beatRange: 0...8, measureRange: 0...1),
                .init(index: 1, beatRange: 8...16, measureRange: 2...3)
            ],
            moments: (0..<16).map { index in
                EngravingReference.Moment(
                    beat: Double(index),
                    notes: left[index].map {
                        .init(pitch: $0, duration: 1, hand: .left)
                    } + right[index].map {
                        .init(pitch: $0, duration: 1, hand: .right)
                    },
                    attack: .block
                )
            }
        )
    }

    @discardableResult
    private static func perform(
        pitch: UInt8,
        timestamp: MIDITimeStamp,
        with follower: EngravingScoreFollower
    ) -> EngravingScoreFollower.Update? {
        let update = follower.consume(noteOn: pitch, timestamp: timestamp)
        follower.consume(noteOff: pitch)
        return update
    }
}
