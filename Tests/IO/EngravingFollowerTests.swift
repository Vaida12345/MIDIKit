import CoreMIDI
import Foundation
import Testing
@testable import MIDIKit

private func engraving(_ chords: [[UInt8]], perLine: Int = 4,
                       hands: [EngravingReference.Hand]? = nil) throws -> EngravingReference {
    let measures = chords.indices.map { EngravingReference.Measure(index: $0 * 10 + 5, onset: Double($0), duration: 1) }
    let lines = stride(from: 0, to: chords.count, by: perLine).enumerated().map { order, start in
        let end = min(chords.count, start + perLine)
        return EngravingReference.Line(index: 100 + order * 7, beatRange: Double(start)...Double(end),
                                       measureRange: measures[start].index...measures[end - 1].index)
    }
    return try EngravingReference(measures: measures, lines: lines, moments: chords.enumerated().map { i, chord in
        .init(beat: Double(i), notes: chord.map { .init(pitch: $0, duration: 1, hand: hands?[i] ?? .right) })
    })
}

private func ticks(_ seconds: Double) -> MIDITimeStamp {
    MIDITimeStamp(seconds / EngravingHostTime.secondsPerTick)
}

private func play(_ pitches: [UInt8], follower: EngravingScoreFollower, start: Double = 1,
                  step: Double = 0.7) -> [EngravingScoreFollower.Update] {
    pitches.enumerated().compactMap { i, pitch in
        follower.consume(.noteOn(pitch: pitch, velocity: 80), timestamp: ticks(start + Double(i) * step))
    }
}

@Suite("Engraving reference and physical input")
struct EngravingFoundationTests {
    @Test func ownershipUsesMeasuresAndScoreOrder() throws {
        let score = try EngravingReference(measures: [
            .init(index: 5, onset: 0, duration: 1), .init(index: 20, onset: 1, duration: 1)
        ], lines: [
            .init(index: 88, beatRange: -1...2, measureRange: 5...5),
            .init(index: 3, beatRange: 0...3, measureRange: 20...20)
        ], moments: [
            .init(beat: 1, notes: [.init(pitch: 60, duration: 0, hand: .left)]),
            .init(beat: 2, notes: [.init(pitch: 62, duration: 1, hand: .right)])
        ])
        let index = EngravingScoreIndex(score)
        #expect(index.moments.map(\.measure) == [20, 20])
        #expect(index.moments.map(\.line) == [1, 1])
        #expect(index.lines.map(\.id) == [88, 3])
        #expect(index.lines[0].extent == 0...1)
        #expect(index.contains(2, in: 1...2))
        #expect(!index.contains(1, in: 0...1))
    }

    @Test func canonicalSharedPitchIsOneAudibleAttack() throws {
        let reference = try EngravingReference(measures: [.init(index: 0, onset: 0, duration: 2)],
            lines: [.init(index: 0, beatRange: 0...2, measureRange: 0...0)], moments: [
                .init(beat: 0, notes: [.init(pitch: 60, duration: 0, hand: .left)]),
                .init(beat: 0.0000001, notes: [.init(pitch: 60, duration: 2, hand: .left),
                                            .init(pitch: 60, duration: 1, hand: .right)], attack: .rolled)
            ])
        let score = EngravingScoreIndex(reference)
        #expect(score.moments.count == 1)
        #expect(score.moments[0].pitches.nonzeroBitCount == 1)
        #expect(score.moments[0].notes.count == 2)
        #expect(score.moments[0].rolled)
    }

    @Test func timestampComparisonsArePairLocal() {
        #expect(EngravingHostTime.seconds(from: 0, to: 100) == nil)
        #expect(EngravingHostTime.seconds(from: 100, to: 100) == nil)
        #expect(EngravingHostTime.seconds(from: 100, to: 1) == nil)
        var tempo = EngravingTempo()
        tempo.observe(beat: 0, time: ticks(1))
        tempo.observe(beat: 1, time: 0)
        tempo.observe(beat: 2, time: ticks(3))
        #expect(abs((tempo.secondsPerBeat ?? 0) - 1) < 0.0001)
        tempo.observe(beat: 3, time: ticks(100))
        #expect(abs((tempo.secondsPerBeat ?? 0) - 1) < 0.0001)
    }

    @Test func velocityZeroAndReattackRemainPhysicalEvents() {
        var input = EngravingInputState()
        let first = input.consume(.noteOn(pitch: 60, velocity: 90), timestamp: ticks(1))
        let second = input.consume(.noteOn(pitch: 60, velocity: 90), timestamp: ticks(1))
        #expect(first.attack == 60 && second.attack == 60)
        #expect(first.id != second.id)
        let release = input.consume(.noteOn(pitch: 60, velocity: 0), timestamp: ticks(2))
        #expect(release.attack == nil && release.released == 60)
        #expect(!input.consume(.noteOff(pitch: 60), timestamp: ticks(3)).changed)
        #expect(!input.consume(.noteOff(pitch: 70), timestamp: ticks(3)).changed)
    }

    @Test func sostenutoCapturesOnlyDepressedKeys() {
        var input = EngravingInputState()
        _ = input.consume(.controlChange(control: 64, value: 0), timestamp: 0)
        _ = input.consume(.noteOn(pitch: 60, velocity: 90), timestamp: ticks(1))
        _ = input.consume(.controlChange(control: 66, value: 127), timestamp: ticks(2))
        _ = input.consume(.noteOn(pitch: 64, velocity: 90), timestamp: ticks(3))
        _ = input.consume(.noteOff(pitch: 60), timestamp: ticks(4))
        _ = input.consume(.noteOff(pitch: 64), timestamp: ticks(4))
        #expect(input.keys[60].sounding)
        #expect(!input.keys[64].sounding)
        _ = input.consume(.controlChange(control: 66, value: 0), timestamp: ticks(5))
        #expect(!input.keys[60].sounding)
    }

    @Test func invalidVisibilityHasNoReadableRegion() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62]]))
        #expect(score.usable(nil) == nil)
        #expect(score.usable(1...1) == nil)
        #expect(score.usable(3...4) == nil)
        #expect(score.usable(-Double.infinity...2) == nil)
        #expect(score.usable(-10...10) == 0...2)
    }
}

@Suite("Engraving musical traces")
struct EngravingMusicalTests {
    @Test func longDistinctiveSequenceDoesNotFreeze() async throws {
        let pitches = (UInt8(20)...100).map { $0 }
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving(pitches.map { [$0] }, perLine: 4))
        var updates: [EngravingScoreFollower.Update] = []
        for (i, pitch) in pitches.enumerated() {
            if let update = follower.consume(.noteOn(pitch: pitch, velocity: 80), timestamp: ticks(1 + Double(i) * 0.7)) { updates.append(update) }
        }
        #expect(updates.last?.beat == 80, "Final updates: \(updates.suffix(4))")
        #expect(updates.last?.state == .tracking)
        #expect(follower.diagnostics.paths <= 128)
        #expect(follower.diagnostics.residuals <= 128)
        #expect(follower.diagnostics.expansions <= 4_096)
    }

    @Test func truncatedRepeatedAcquisitionRecoversOnDistinguishingContinuation() async throws {
        var pitches = (0..<400).map { UInt8($0 % 2 == 0 ? 60 : 62) }
        pitches.replaceSubrange(302...306, with: [71, 73, 75, 77, 79])
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving(pitches.map { [$0] }))
        #expect(play([60, 62], follower: follower).isEmpty)
        var recovered: [EngravingScoreFollower.Update] = []
        for (i, pitch) in [UInt8(71), 73, 75].enumerated() {
            if let update = follower.consume(.noteOn(pitch: pitch, velocity: 80), timestamp: ticks(3 + Double(i))) { recovered.append(update) }
        }
        #expect(recovered.last?.beat == 304, "\(recovered)")
        #expect(follower.diagnostics.destinations <= 64)
        #expect(follower.diagnostics.expansions <= 4_096)
    }
    @Test func noReferenceAndNeutralEventsDoNotAcquire() async throws {
        let follower = EngravingScoreFollower()
        #expect(follower.consume(.noteOn(pitch: 60, velocity: 80), timestamp: 0) == nil)
        await follower.update(reference: try engraving([[60], [62]]))
        #expect(follower.consume(.noteOff(pitch: 60), timestamp: ticks(1)) == nil)
        #expect(follower.consume(.controlChange(control: 64, value: 127), timestamp: ticks(2)) == nil)
    }

    @Test func oneHandAndDelayedOtherHandDoNotDoubleAdvance() async throws {
        let notes: [[UInt8]] = [[48, 60], [50, 62], [52, 64], [53, 65], [55, 67]]
        let reference = try EngravingReference(measures: [.init(index: 0, onset: 0, duration: 5)],
            lines: [.init(index: 0, beatRange: 0...5, measureRange: 0...0)],
            moments: notes.enumerated().map { i, chord in .init(beat: Double(i), notes: chord.map {
                .init(pitch: $0, duration: 2, hand: $0 < 60 ? .left : .right)
            }) })
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        let first = play([60, 62], follower: follower)
        #expect(first.last?.beat == 1)
        let lagging = play([48, 50], follower: follower, start: 2.5, step: 0.03)
        #expect(lagging.allSatisfy { $0.beat <= 1 && !$0.didReframe })
        let next = play([64, 65, 67], follower: follower, start: 3)
        #expect(next.last?.beat == 4)
    }

    @Test func participationAdaptsWhenTheOtherLaneJoins() async throws {
        let reference = try EngravingReference(measures: [.init(index: 0, onset: 0, duration: 8)],
            lines: [.init(index: 0, beatRange: 0...8, measureRange: 0...0)],
            moments: (0..<8).map { i in .init(beat: Double(i), notes: [
                .init(pitch: UInt8(40 + i), duration: 1, hand: .left),
                .init(pitch: UInt8(70 + i), duration: 1, hand: .right)
            ]) })
        let follower = EngravingScoreFollower()
        await follower.update(reference: reference)
        let right = play([70, 71, 72, 73], follower: follower)
        #expect(right.last?.activeHands == .right)
        var joined: [EngravingScoreFollower.Update] = []
        for i in 4..<8 {
            joined += play([UInt8(70 + i), UInt8(40 + i)], follower: follower, start: Double(i + 1), step: 0.04)
        }
        #expect(joined.last?.beat == 7)
        #expect(joined.last?.activeHands == .both)
    }

    @Test func navigationRetainsOnlyBroadCalibration() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60, 64], [62, 65], [67, 71], [69, 72], [74, 77]]))
        for (i, notes) in [[UInt8(60), 64], [62, 65], [67, 71], [69, 72]].enumerated() {
            _ = play(notes, follower: follower, start: Double(i + 1), step: 0.03)
        }
        let samples = follower.diagnostics.calibration
        #expect(samples > 0)
        follower.userReset()
        #expect(follower.diagnostics.calibration == samples)
        #expect(follower.diagnostics.paths == 0)
        follower.reset()
        #expect(follower.diagnostics.calibration == 0)
    }

    @Test func omittedFirstWrittenOnsetStillAllowsActualLineEntry() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60], [62], [64], [65]], perLine: 2))
        follower.visibleRange = 0...2
        let updates = play([60, 62, 65], follower: follower)
        #expect(updates.last?.beat == 3)
        #expect(updates.last?.viewport == .advance(toLine: 107))
    }

    @Test func deterministicReplayAndPublicationInvariants() async throws {
        let reference = try engraving([[60], [62], [64], [65], [67], [69]], perLine: 2)
        let a = EngravingScoreFollower(), b = EngravingScoreFollower()
        await a.update(reference: reference)
        await b.update(reference: reference)
        a.visibleRange = 0...2
        b.visibleRange = 0...2
        var previous: EngravingScoreFollower.Update?
        for (i, pitch) in [UInt8(60), 62, 99, 64, 65, 60, 62, 64, 65, 67, 69].enumerated() {
            let event = ParsedInputEvent.noteOn(pitch: pitch, velocity: 80)
            let update = a.consume(event, timestamp: ticks(Double(i + 1)))
            #expect(update == b.consume(event, timestamp: ticks(Double(i + 1))))
            guard let update else { continue }
            #expect((0...1).contains(update.confidence))
            if update.state != .tracking { #expect(update.viewport == .unchanged) }
            if let previous {
                #expect(update.displayBeat >= previous.displayBeat || update.didReframe)
                if update.beat == previous.beat, update.displayBeat == previous.displayBeat,
                   update.state == previous.state, update.activeHands == previous.activeHands,
                   update.viewportRevision == previous.viewportRevision {
                    #expect(abs(update.confidence - previous.confidence) >= 0.05)
                }
            }
            previous = update
        }
    }

    @Test func pedalOverlapDoesNotDelayProgress() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60], [62], [64], [65]]))
        _ = follower.consume(.controlChange(control: 64, value: 127), timestamp: ticks(0.5))
        _ = play([60], follower: follower)
        _ = follower.consume(.noteOff(pitch: 60), timestamp: ticks(1.2))
        #expect(play([62, 64, 65], follower: follower, start: 2).last?.beat == 3)
    }

    @Test(arguments: [true, false])
    func scoredRepetitionsSurviveMissingReleases(releases: Bool) async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[48], [60], [60], [62], [64]]))
        var updates: [EngravingScoreFollower.Update] = []
        for (i, pitch) in [UInt8(48), 60, 60, 62, 64].enumerated() {
            if let update = follower.consume(.noteOn(pitch: pitch, velocity: 80), timestamp: ticks(1 + Double(i))) { updates.append(update) }
            if releases { _ = follower.consume(.noteOff(pitch: pitch), timestamp: ticks(1.5 + Double(i))) }
        }
        #expect(updates.last?.beat == 4)
    }

    @Test func offscreenRestartRevealsCurrentCorroboratedBeat() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[40], [42], [44], [46], [48], [50], [60], [62], [64], [66], [68]], perLine: 3))
        follower.visibleRange = 6...11
        _ = play([60, 62, 64], follower: follower)
        let restart = play([40, 42, 44], follower: follower, start: 6)
        #expect(restart.last?.beat == 2)
        #expect(restart.contains { $0.viewport == .jump(toLine: 100) && $0.beat >= 1 })
        #expect(restart.filter(\.didReframe).allSatisfy { $0.displayBeat == $0.beat })
    }

    @Test func oneRemoteLookingCohortCannotJump() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[40], [42], [44], [46], [60], [62], [64], [65]], perLine: 4))
        follower.visibleRange = 4...8
        _ = play([60, 62], follower: follower)
        let anomaly = play([40, 42, 44, 46], follower: follower, start: 4, step: 0.003)
        #expect(anomaly.allSatisfy { $0.viewport == .unchanged })
        let recovery = play([64, 65], follower: follower, start: 5)
        #expect(recovery.last?.beat == 7, "\(recovery)")
    }

    @Test func separateRemoteErrorsCannotAccumulateAJump() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[40], [42], [44], [46], [60], [62], [64], [65], [67], [69]], perLine: 4))
        follower.visibleRange = 4...10
        let updates = play([60, 62, 40, 64, 65, 42, 67, 69], follower: follower)
        #expect(updates.allSatisfy { !$0.didReframe })
        #expect(updates.last?.beat == 9)
    }

    @Test func finalAttackHoldsWithoutSyntheticEndOrControlAdvancement() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60], [62], [64]]))
        _ = play([60, 62, 64], follower: follower)
        var changes: [EngravingScoreFollower.Update] = []
        for i in 0..<20 {
            if let update = follower.consume(.controlChange(control: 1, value: UInt8(i)), timestamp: ticks(100 + Double(i))) { changes.append(update) }
        }
        #expect(changes.allSatisfy { $0.beat == 2 && $0.displayBeat == 2 && $0.viewport == .unchanged })
    }

    @Test func referenceReplacementClearsOldLayoutAndPhysicalState() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60], [62], [64], [65]], perLine: 2))
        follower.visibleRange = 0...2
        _ = play([60, 62, 64], follower: follower)
        await follower.update(reference: try engraving([[70], [72]]))
        #expect(follower.visibleRange == nil)
        #expect(follower.consume(.noteOff(pitch: 64), timestamp: ticks(5)) == nil)
        let update = play([70], follower: follower, start: 6).last
        #expect(update?.beat == 0 && update?.viewportRevision == 0)
    }

    @Test func ordinaryMelodyAdvancesOnEnteredLine() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60], [62], [64], [65], [67], [69]], perLine: 3))
        follower.visibleRange = 0...3
        let updates = play([60, 62, 64, 65], follower: follower)
        #expect(updates.last?.beat == 3)
        #expect(updates.last?.viewport == .advance(toLine: 107))
        #expect(updates.dropLast().allSatisfy { $0.viewport == .unchanged })
    }

    @Test func distinctivePartialChordAcquiresBeforeCompletion() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[40], [60, 64, 67, 71], [72]]))
        let update = follower.consume(.noteOn(pitch: 64, velocity: 80), timestamp: ticks(1))
        #expect(update?.beat == 1)
        #expect(update?.viewport == .unchanged)
    }

    @Test func extraChordToneDoesNotPoisonLateMember() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60, 64, 67, 71], [72], [74]]))
        let chord = play([60, 64, 67, 70, 71], follower: follower, step: 0.025)
        #expect(chord.allSatisfy { $0.beat == 0 && $0.viewport == .unchanged })
        let next = play([72], follower: follower, start: 2)
        #expect(next.last?.beat == 1)
    }

    @Test(arguments: [0.005, 0.5, 2.0])
    func slowRollAndFastSerializationRemainOneOnset(step: Double) async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60, 64, 67, 71], [72]]))
        let chord = play([60, 64, 67, 71], follower: follower, step: step)
        #expect(chord.allSatisfy { $0.beat == 0 && !$0.didReframe })
    }

    @Test func initialMistakesAndLocalOmissionsRecover() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60], [62], [64], [65], [67]]))
        let updates = play([99, 60, 61, 63, 64, 67], follower: follower)
        #expect(updates.last?.beat == 4)
        #expect(updates.last?.state == .tracking)
    }

    @Test func invalidTimestampsPreserveSequenceFollowing() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60], [62], [64], [65]]))
        let times: [MIDITimeStamp] = [ticks(2), 0, ticks(2), 1]
        let updates = zip([UInt8(60), 62, 64, 65], times).compactMap {
            follower.consume(.noteOn(pitch: $0.0, velocity: 90), timestamp: $0.1)
        }
        #expect(updates.last?.beat == 3)
        #expect(updates.allSatisfy { $0.confidence.isFinite })
    }

    @Test func pauseResumesLocally() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60], [62], [64]]))
        _ = play([60, 62], follower: follower)
        let next = play([64], follower: follower, start: 100)
        #expect(next.last?.beat == 2)
        #expect(next.last?.didReframe == false)
    }

    @Test func visibleReplayHoldsMarkerUntilCatchup() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60], [62], [64], [65], [67], [69]], perLine: 6))
        follower.visibleRange = 0...6
        _ = play([60, 62, 64, 65, 67], follower: follower)
        let replay = play([60, 62, 64], follower: follower, start: 6)
        #expect(replay.last?.beat == 2)
        #expect(replay.last?.displayBeat == 4)
        #expect(replay.allSatisfy { $0.viewport == .unchanged })
    }

    @Test func hardResetEqualsFreshInstance() async throws {
        let reference = try engraving([[60], [62], [64], [65]])
        let used = EngravingScoreFollower()
        let fresh = EngravingScoreFollower()
        await used.update(reference: reference)
        await fresh.update(reference: reference)
        used.visibleRange = 0...4
        _ = play([60, 62, 64], follower: used)
        used.reset()
        #expect(used.visibleRange == nil)
        #expect(used.diagnostics.calibration == 0)
        #expect(play([62, 64, 65], follower: used) == play([62, 64, 65], follower: fresh))
    }

    @Test func userResetRetainsRangeButRevokesAcquisition() async throws {
        let follower = EngravingScoreFollower()
        await follower.update(reference: try engraving([[60, 64], [67]]))
        follower.visibleRange = 0...2
        _ = play([60], follower: follower)
        follower.userReset()
        #expect(follower.visibleRange == 0...2)
        #expect(follower.consume(.noteOff(pitch: 60), timestamp: ticks(3)) == nil)
        #expect(play([67], follower: follower, start: 4).last?.beat == 1)
    }

    @Test func overloadsAndLineWrappingPreserveMusicalResults() async throws {
        let chords: [[UInt8]] = [[60], [62], [64], [65], [67], [69]]
        let a = EngravingScoreFollower()
        let b = EngravingScoreFollower()
        await a.update(reference: try engraving(chords, perLine: 2))
        await b.update(reference: try engraving(chords, perLine: 3))
        for (i, chord) in chords.enumerated() {
            let event = ParsedInputEvent.noteOn(pitch: chord[0], velocity: 80)
            let timestamp = ticks(1 + Double(i))
            let direct = a.consume(event, timestamp: timestamp)
            let wrapped = b.consume(MIDIInputEvent(timestamp: timestamp, event: event, channel: 9))
            #expect(direct?.beat == wrapped?.beat)
            #expect(direct?.confidence == wrapped?.confidence)
            #expect(direct?.activeHands == wrapped?.activeHands)
        }
    }
}

private func path(_ offset: Int, episode: UInt64 = 1, onsets: Int = 4) -> EngravingPath {
    EngravingPath(current: EngravingAssignment(offset: offset, pitches: 1, firstTime: ticks(1), lastTime: ticks(2)),
                  hands: .right, episode: episode, start: 0, onsets: onsets, onsetEvidence: 10,
                  lastObservation: UInt64(offset + 100), lastAttack: 60)
}

private func certain(_ path: EngravingPath, support: Double = 1) -> EngravingEvidence {
    EngravingEvidence(paths: [.init(path: path, logMass: log(support))], residualLogMass: log(1 - support),
                      noiseLogMass: -.infinity, totalLogMass: 0, best: path)
}

@Suite("Engraving presentation authority")
struct EngravingPresentationTests {
    @Test func largeOmissionWithinAdjacentLineStillUsesTheDirectGate() throws {
        let score = EngravingScoreIndex(try engraving((UInt8(60)...71).map { [$0] }, perLine: 6))
        var policy = EngravingPresentation()
        policy.report(0...6, score: score)
        let before = path(5)
        var entry = path(10)
        entry.skippedAttacks = true
        entry.recoveryOnsets = 1
        entry.omittedAttacks = 4
        entry.omissionStart = 6
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .unchanged)
        entry.current.offset = 11
        entry.recoveryOnsets = 2
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .jump(toLine: 107))
    }
    @Test func earlyHandCannotRemoveStillNeededOtherHandNotation() throws {
        let score = EngravingScoreIndex(try engraving([[48, 60], [50, 62], [52, 64], [53, 65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        let before = path(1)
        var leading = path(2)
        leading.hands = .both
        leading.leftAssignments = 2
        leading.rightAssignments = 2
        leading.previous = EngravingAssignment(offset: 1, pitches: EngravingScoreIndex.mask(50), firstTime: ticks(1), lastTime: ticks(2))
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        #expect(policy.consume(path: leading, evidence: certain(leading), state: .tracking, fresh: true, score: score) == .unchanged)
        leading.previous?.pitches |= EngravingScoreIndex.mask(62)
        #expect(policy.consume(path: leading, evidence: certain(leading), state: .tracking, fresh: true, score: score) == .advance(toLine: 107))
    }

    @Test func postJumpHysteresisStillAllowsSustainedCorrection() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        let jumped = path(3)
        #expect(policy.consume(path: jumped, evidence: certain(jumped), state: .tracking, fresh: true, score: score) == .jump(toLine: 107))
        policy.report(2...4, score: score)
        _ = policy.consume(path: jumped, evidence: certain(jumped), state: .tracking, fresh: false, score: score)
        var correction = path(0, episode: 200)
        correction.lastObservation = 205
        correction.advanced = true
        #expect(policy.consume(path: correction, evidence: certain(correction, support: 0.997), state: .tracking, fresh: true, score: score) == .unchanged)
        correction.current.offset = 1
        correction.lastObservation = 206
        #expect(policy.consume(path: correction, evidence: certain(correction, support: 0.997), state: .tracking, fresh: true, score: score) == .jump(toLine: 100))
        #expect(policy.displayBeat == 1)
    }
    @Test func skippedUnreadMaterialNeedsDestinationCorroboration() throws {
        let score = EngravingScoreIndex(try engraving((UInt8(60)...69).map { [$0] }, perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        let before = path(1)
        var skipped = path(6)
        skipped.skippedAttacks = true
        skipped.recoveryOnsets = 1
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        #expect(policy.consume(path: skipped, evidence: certain(skipped), state: .tracking, fresh: true, score: score) == .unchanged)
        var confirmed = path(7)
        confirmed.skippedAttacks = true
        confirmed.recoveryOnsets = 2
        #expect(policy.consume(path: confirmed, evidence: certain(confirmed), state: .tracking, fresh: true, score: score) == .jump(toLine: 121))
    }

    @Test func conflictingDestinationsAndUnknownVisibilityNeverAuthorizeMovement() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        let entry = path(2)
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .unchanged)
        policy.report(0...2, score: score)
        let conflicting = EngravingEvidence(paths: [.init(path: entry, logMass: log(0.5)), .init(path: path(0, episode: 2), logMass: log(0.5))],
            residualLogMass: -.infinity, noiseLogMass: -.infinity, totalLogMass: 0, best: entry)
        #expect(policy.consume(path: entry, evidence: conflicting, state: .tracking, fresh: true, score: score) == .unchanged)
    }

    @Test func alreadyReceivedEntryCanBeResolvedWithoutAnotherOnset() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        let before = path(1), entry = path(2)
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        _ = policy.consume(path: entry, evidence: certain(entry, support: 0.96), state: .tracking, fresh: true, score: score)
        // The same already-received attack is now resolved; its observation/onset count is unchanged.
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .advance(toLine: 107))
    }
    @Test func alreadyVisibleLineDoesNotAdvanceButCanBeRevealedAfterClipping() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...4, score: score)
        let before = path(1), entry = path(2)
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .unchanged)
        policy.report(0...2.5, score: score)
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .advance(toLine: 107))
    }

    @Test func aSliverOfTargetLineIsNotWholeLineReadability() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2.01, score: score)
        let before = path(1), entry = path(2)
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .advance(toLine: 107))
    }

    @Test func initialOffscreenAcquisitionNeverUsesAdvance() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        var single = path(2, onsets: 1)
        single.onsetEvidence = 0
        #expect(policy.consume(path: single, evidence: certain(single), state: .tracking, fresh: true, score: score) == .unchanged)
        let corroborated = path(3, onsets: 2)
        #expect(policy.consume(path: corroborated, evidence: certain(corroborated), state: .tracking, fresh: true, score: score) == .jump(toLine: 107))
    }

    @Test func visibleReplayCancelsADeferredAdvanceAndHoldsFrontier() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        let before = path(1), entry = path(2), replay = path(0, episode: 9)
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        _ = policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score)
        let revision = policy.revision
        #expect(policy.consume(path: replay, evidence: certain(replay), state: .tracking, fresh: true, score: score) == .unchanged)
        #expect(policy.revision > revision)
        #expect(policy.displayBeat == 2)
        #expect(policy.pending == nil)
    }

    @Test func refusalDoesNotCauseAChordToneRetryStorm() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        let before = path(1), entry = path(2)
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        _ = policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score)
        policy.report(0...2, score: score)
        for _ in 0..<10 { #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .unchanged) }
    }

    @Test func successorAcrossEmptySystemsUsesDirectReveal() throws {
        let reference = try EngravingReference(measures: (0..<4).map { .init(index: $0, onset: Double($0), duration: 1) },
            lines: (0..<4).map { .init(index: $0 * 10, beatRange: Double($0)...Double($0 + 1), measureRange: $0...$0) },
            moments: [0.0, 0.5, 3.0].enumerated().map { .init(beat: $0.element, notes: [.init(pitch: UInt8(60 + $0.offset), duration: 0.5, hand: .right)]) })
        let score = EngravingScoreIndex(reference)
        var policy = EngravingPresentation()
        policy.report(0...1, score: score)
        let predecessor = path(1), successor = path(2)
        _ = policy.consume(path: predecessor, evidence: certain(predecessor), state: .tracking, fresh: true, score: score)
        #expect(policy.consume(path: successor, evidence: certain(successor), state: .tracking, fresh: true, score: score) == .jump(toLine: 30))
    }
    @Test func delayedHandoffDoesNotRequireAnotherLineChange() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65], [67], [69]], perLine: 3))
        var policy = EngravingPresentation()
        policy.report(0...3, score: score)
        let before = path(2), entry = path(3), later = path(4)
        #expect(policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score) == .unchanged)
        #expect(policy.consume(path: entry, evidence: certain(entry, support: 0.96), state: .tracking, fresh: true, score: score) == .unchanged)
        #expect(policy.consume(path: later, evidence: certain(later), state: .tracking, fresh: true, score: score) == .advance(toLine: 107))
    }

    @Test func uncertaintyCancelsQueuedAdvance() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        let before = path(1), entry = path(2)
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .advance(toLine: 107))
        let revision = policy.revision
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .uncertain, fresh: false, score: score) == .unchanged)
        #expect(policy.revision > revision)
        #expect(policy.pending == nil)
        #expect(policy.handoff != nil)
    }

    @Test func partialFulfillmentSuppressesRetryUntilProgressLeavesView() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65], [67], [69]], perLine: 3))
        var policy = EngravingPresentation()
        policy.report(0...3, score: score)
        let before = path(2), entry = path(3), next = path(4)
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        _ = policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score)
        policy.report(2...3.5, score: score)
        #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .unchanged)
        #expect(policy.consume(path: next, evidence: certain(next), state: .tracking, fresh: true, score: score) == .advance(toLine: 107))
    }

    @Test func pendingRequestIsNotAssumedExecuted() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        let before = path(1), entry = path(2)
        _ = policy.consume(path: before, evidence: certain(before), state: .tracking, fresh: true, score: score)
        _ = policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score)
        let revision = policy.revision
        for _ in 0..<10 { #expect(policy.consume(path: entry, evidence: certain(entry), state: .tracking, fresh: true, score: score) == .unchanged) }
        #expect(policy.visibility == 0...2)
        #expect(policy.revision == revision)
    }

    @Test func noAnticipationOrActionFromSilenceAndControls() throws {
        let score = EngravingScoreIndex(try engraving([[60], [62], [64], [65]], perLine: 2))
        var policy = EngravingPresentation()
        policy.report(0...2, score: score)
        let final = path(1)
        for fresh in [true, false, false] {
            #expect(policy.consume(path: final, evidence: certain(final), state: .tracking, fresh: fresh, score: score) == .unchanged)
        }
        #expect(policy.pending == nil)
    }
}
