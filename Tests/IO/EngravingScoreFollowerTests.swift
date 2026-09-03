//
//  EngravingScoreFollowerTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-09-03.
//

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

    @Test("musical evidence can override the initial viewport hint")
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
        let update = Self.perform(pitch: 90, timestamp: 2_000, with: follower)

        #expect(update?.beat == 9)
        #expect(update?.displayBeat == 9)
        #expect(update?.measureIndex == 2)
        #expect(update?.didRelocate == true)
        #expect(update?.viewport == .jump(toLine: 2))
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
        #expect(update?.didRelocate == false)
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
        #expect(confirmedReplay?.didRelocate == false)

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
        #expect(movedPastFrontier?.viewport == .advance(toLine: 30))
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
            #expect(!current.didRelocate)
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
        #expect(mistake?.didRelocate == false)
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

    @Test("two coherent distinguishing gestures can activate a similar remote passage")
    func distinguishingSequenceActivatesRemotePassage() async throws {
        let local: [[UInt8]] = [
            [48, 55, 60, 64], [47, 55, 59, 62], [45, 52, 57, 60], [43, 50, 55, 59]
        ]
        let remote: [[UInt8]] = [
            [48, 55, 60, 65], [47, 55, 59, 64], [45, 52, 57, 62], [43, 50, 55, 60]
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
        var updates: [EngravingScoreFollower.Update] = []
        for chord in Array(local.prefix(2)) + Array(remote.suffix(2)) {
            for pitch in chord {
                if let update = follower.consume(noteOn: pitch, timestamp: timestamp) {
                    updates.append(update)
                }
                timestamp += 1_000
                follower.consume(noteOff: pitch)
            }
        }

        let relocation = try #require(updates.first(where: { $0.didRelocate }))
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

        let relocationOffset = try #require(updates.firstIndex(where: { $0.didRelocate }))
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

        let jumpOffset = try #require(updates.firstIndex(where: { $0.didRelocate }))
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

    @Test("the viewport advances only after committed entry into the next line")
    func viewportAdvancesAtLineEntry() async throws {
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

        #expect(updates.prefix(8).allSatisfy { $0.viewport == .unchanged })
        #expect(updates[8].viewport == .advance(toLine: 200))
        #expect(updates.dropFirst(9).allSatisfy { $0.viewport == .unchanged })
        let recommendations = updates.compactMap { update -> Int? in
            guard case let .advance(toLine: line) = update.viewport else { return nil }
            return line
        }
        #expect(recommendations.count == 1)
        #expect(recommendations.first == 200)
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
            #expect(updates.last?.beat == Double(expectedIndex))
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
        for chord in remote.prefix(3) {
            for pitch in chord {
                if let update = follower.consume(noteOn: pitch, timestamp: timestamp) {
                    remoteUpdates.append(update)
                }
                timestamp += 1_000
            }
            for pitch in chord { follower.consume(noteOff: pitch) }
        }

        let jump = try #require(remoteUpdates.first(where: { $0.didRelocate }))
        #expect(jump.beat >= 8)
        #expect(jump.viewport == .jump(toLine: 2))
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

        #expect(mistake?.didRelocate == false)
        #expect(recovered?.didRelocate == false)
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

        #expect(ambiguousAnchor?.didRelocate == false)
        #expect(ambiguousAnchor?.beat == 2)
        #expect(recovered?.didRelocate == false)
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
        #expect(update?.didRelocate == false)
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
        #expect(update?.didRelocate == false)
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
