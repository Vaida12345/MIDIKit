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
        #expect(update?.measureIndex == 2)
        #expect(update?.didRelocate == false)
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

    @Test("replays backward inside one measure without relocating")
    func replaysBackwardInsideMeasure() async throws {
        let pitches: [UInt8] = [60, 62, 64, 65]
        let reference = try EngravingReference(
            measures: [.init(index: 0, onset: 0, duration: 4)],
            lines: [.init(index: 0, beatRange: 0...4, measureRange: 0...0)],
            moments: pitches.enumerated().map {
                Self.rightMoment(beat: Double($0.offset), pitches: [$0.element])
            }
        )
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        follower.visibleRange = 0...4

        var timestamp: MIDITimeStamp = 1_000
        var relocations = 0
        var update: EngravingScoreFollower.Update?
        for index in [0, 1, 2, 3, 1, 2, 3] {
            update = Self.perform(pitch: pitches[index], timestamp: timestamp, with: follower)
            if update?.didRelocate == true { relocations += 1 }
            timestamp += 1_000
        }

        #expect(update?.beat == 3)
        #expect(relocations == 0)
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

    @Test("nearby mistakes do not activate an off-screen passage")
    func mistakesDoNotActivateRemotePassage() async throws {
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

        #expect(updates.allSatisfy { !$0.didRelocate })
        #expect(updates.last?.measureIndex == 0)
    }

    @Test("a distant relocation requires sustained distinguishing evidence")
    func distantRelocationRequiresSustainedEvidence() async throws {
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

        #expect(updates.dropLast().allSatisfy { !$0.didRelocate })
        #expect(updates.last?.didRelocate == true)
        #expect(updates.last?.beat == 39)
        #expect(updates.last?.state == .tracking)
    }

    @Test("viewport recommendations occur once per required line change")
    func viewportRecommendationsAreSparse() async throws {
        let pitches = (60..<68).map(UInt8.init)
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
        follower.visibleRange = 0...4

        var recommendations: [EngravingScoreFollower.ViewportRecommendation] = []
        for (index, pitch) in pitches.enumerated() {
            if let update = Self.perform(
                pitch: pitch,
                timestamp: MIDITimeStamp(index + 1) * 1_000,
                with: follower
            ), case .ensureVisible = update.viewport {
                recommendations.append(update.viewport)
            }
        }

        #expect(recommendations.count == 1)
        #expect(recommendations.first == .ensureVisible(measures: 1...1, preferredCenter: 1))
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
