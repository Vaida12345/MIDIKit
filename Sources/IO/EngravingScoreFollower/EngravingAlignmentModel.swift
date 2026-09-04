//
//  EngravingAlignmentModel.swift
//  MIDIKit
//

import CoreMIDI
import Foundation


enum EngravingAlignmentMovement: UInt8 {
    case held
    case continuous
    case recovered
    case replay
    case jump
}

struct EngravingAlignmentResult {
    let gestureIndex: Int
    let confidence: Double
    let state: EngravingScoreFollower.TrackingState
    let activeHands: EngravingScoreFollower.HandParticipation
    let movement: EngravingAlignmentMovement
}

/// Bounded joint filter over score position, onset membership, hand interpretation, tempo, and
/// continuity versus a new performance episode.
///
/// The important modeling choice is that serialized MIDI is never committed to a chord before
/// alignment. Every hypothesis independently decides whether an attack extends its present onset,
/// advances locally, repairs omissions, or begins a new episode.
struct EngravingAlignmentModel {
    private enum Configuration {
        static let beamWidth = 96
        static let continuityBeamWidth = 64
        static let statesPerDestination = 3
        static let candidatesPerMode = 24
        static let localDeletionDepth = 3
        static let localNeighborhoodDepth = 4
        static let lostRecoveryDepth = 12
        static let localNeighborhoodBeatDistance = 4.0
        static let lostRecoveryBeatDistance = 16.0

        static let insertionPenalty = 1.35
        static let missingNotePenalty = 0.48
        static let maximumClosurePenalty = 2.8
        static let deletionPenalty = 1.15
        static let handModeChangePenalty = 0.55
        static let ordinaryRestartPenalty = 4.1
        static let lostRestartDiscount = 1.35
        static let postReframePenalty = 1.15
    }

    private struct Hypothesis {
        var index: Int
        var mode: EngravingHandMode
        var observedMask: UInt128
        var unexpectedMask: UInt128
        var onsetStartedAt: MIDITimeStamp?
        var lastAttackAt: MIDITimeStamp?
        var completedOnsetSpanTicks: Double?
        var completedOnsetAttack: EngravingReference.Attack?
        var logWeight: Double
        var clock: PerformanceTempoTracker

        var isRestart: Bool
        var episodeStartIndex: Int
        var episodeOnsets: Int
        var coherentOnsets: Int
        var currentHasContradiction: Bool
        var consecutiveUnexpectedAttacks: Int
        var lookupIsExhaustive: Bool
        var preferredLookupIsExhaustive: Bool
    }

    private struct HypothesisKey: Hashable {
        let index: Int
        let mode: EngravingHandMode
        let observedMask: UInt128
        let isRestart: Bool
        let episodeStartIndex: Int
        let episodeOnsets: Int
        let coherentOnsets: Int
        let currentHasContradiction: Bool
        let consecutiveUnexpectedAttacks: Int
        let onsetStartedAt: MIDITimeStamp?
        let lastAttackAt: MIDITimeStamp?
        let completedOnsetSpanTicks: Double?
        let completedOnsetAttack: EngravingReference.Attack?
        let clockLogTicksPerBeat: Double?
        let clockLogDeviation: Double
        let clockSampleCount: Int
        let clockLastTimestamp: MIDITimeStamp?
        let clockLastBeat: Double?
        let lookupIsExhaustive: Bool
        let preferredLookupIsExhaustive: Bool
    }

    private struct DestinationEvidence {
        var mass = 0.0
        var bestHypothesis: Int = 0
        var bestWeight = -Double.infinity
    }

    private struct DestinationClassKey: Hashable {
        let index: Int
        let isRestart: Bool
    }

    let score: EngravingScoreFeatureIndex

    private var hypotheses: [Hypothesis] = []
    private var timing = PerformanceTimingModel()
    private var acquisitionRange: ClosedRange<Double>?
    private var visibleRange: ClosedRange<Double>?

    private(set) var committedIndex: Int?
    private var forwardFrontier: Int?
    private var lastState: EngravingScoreFollower.TrackingState = .uncertain
    private var weakEventStreak = 0
    private var postReframeRecovery = 0

    private var leftEvidence = 0.0
    private var rightEvidence = 0.0
    private var participation: EngravingScoreFollower.HandParticipation = .unknown

    init(score: EngravingScoreFeatureIndex) {
        self.score = score
    }

    var hasAcquisitionEvidence: Bool { !hypotheses.isEmpty }

    mutating func hardReset(acquisitionRange: ClosedRange<Double>?) {
        timing.hardReset()
        resetPosition(acquisitionRange: acquisitionRange)
    }

    /// Begins a user-directed acquisition epoch while retaining performer calibration.
    mutating func userReset(acquisitionRange: ClosedRange<Double>?) {
        resetPosition(acquisitionRange: acquisitionRange)
    }

    mutating func setVisibleRange(_ range: ClosedRange<Double>?) {
        visibleRange = range
    }

    mutating func consume(_ attack: PerformanceNoteAttack) -> EngravingAlignmentResult? {
        guard !score.gestures.isEmpty else { return nil }
        let bit = EngravingScoreFeatureIndex.pitchBit(attack.pitch)

        var expanded: [Hypothesis] = []
        expanded.reserveCapacity(hypotheses.count * 8 + Configuration.candidatesPerMode * 3)
        for hypothesis in hypotheses {
            appendStay(hypothesis, attack: attack, bit: bit, to: &expanded)
            appendSameOnsetHandInterpretations(
                hypothesis,
                attack: attack,
                bit: bit,
                to: &expanded
            )
            appendLocalTransitions(hypothesis, attack: attack, bit: bit, to: &expanded)
        }

        if committedIndex == nil {
            appendIndexedSeeds(
                attack: attack,
                bit: bit,
                restart: false,
                // Fresh seeds let acquisition recover from an initial mistake, but continuing
                // a coherent sequence must be preferred to forgetting the preceding evidence.
                penalty: hypotheses.isEmpty ? 0 : 2.8,
                to: &expanded
            )
        } else {
            appendLocalRecoverySeeds(
                attack: attack,
                bit: bit,
                depth: lastState == .lost
                    ? Configuration.lostRecoveryDepth
                    : Configuration.localNeighborhoodDepth,
                penalty: lastState == .lost ? 0.9 : (lastState == .uncertain ? 1.5 : 2.6),
                to: &expanded
            )
            let pause = bestContinuityClock()?.pauseEvidence(at: attack.timestamp) ?? 0
            var penalty = Configuration.ordinaryRestartPenalty - pause
            if lastState == .lost { penalty -= Configuration.lostRestartDiscount }
            if postReframeRecovery > 0 { penalty += Configuration.postReframePenalty }
            appendIndexedSeeds(
                attack: attack,
                bit: bit,
                restart: true,
                penalty: max(1.8, penalty),
                to: &expanded
            )
        }

        hypotheses = prune(expanded)
        guard !hypotheses.isEmpty else { return nil }

        if committedIndex == nil {
            return commitAcquisitionIfReady()
        }
        return publishTrackingResult(for: attack, bit: bit)
    }

    mutating func consume(_ release: PerformanceNoteRelease) {
        guard let dwell = release.dwellTicks else { return }
        var deltas: [Double] = []
        deltas.reserveCapacity(hypotheses.count)
        var minimumDelta = Double.infinity
        var maximumDelta = -Double.infinity
        for hypothesis in hypotheses {
            let delta: Double
            if let duration = score.gestures[hypothesis.index].duration(
                of: release.pitch,
                mode: hypothesis.mode
            ) {
                delta = timing.dwellLogLikelihood(
                    ticks: dwell,
                    writtenBeats: duration
                )
            } else {
                delta = 0
            }
            deltas.append(delta)
            minimumDelta = min(minimumDelta, delta)
            maximumDelta = max(maximumDelta, delta)
        }
        // A common additive likelihood cannot change any posterior or pruning decision.
        if maximumDelta - minimumDelta > 1e-12 {
            for offset in hypotheses.indices {
                hypotheses[offset].logWeight += deltas[offset]
            }
            hypotheses = prune(hypotheses)
        }

        guard let committedIndex, score.gestures.indices.contains(committedIndex) else { return }
        let gesture = score.gestures[committedIndex]
        for mode in EngravingHandMode.allCases {
            if let duration = gesture.duration(of: release.pitch, mode: mode) {
                timing.observeDwell(ticks: dwell, writtenBeats: duration)
                break
            }
        }
    }

    // MARK: - Expansion

    private func appendStay(
        _ source: Hypothesis,
        attack: PerformanceNoteAttack,
        bit: UInt128,
        to result: inout [Hypothesis]
    ) {
        let expected = score.gestures[source.index].mask(for: source.mode)
        var candidate = source
        candidate.observedMask |= bit
        if expected & bit == 0 { candidate.unexpectedMask |= bit }
        candidate.lastAttackAt = attack.timestamp ?? source.lastAttackAt

        let wasAlreadyObserved = source.observedMask & bit != 0
        if expected & bit != 0 {
            candidate.logWeight += wasAlreadyObserved ? -0.30 : 1.55
            candidate.consecutiveUnexpectedAttacks = 0
            if wasAlreadyObserved, attack.wasReleasedSincePreviousAttack {
                // Re-articulation is a boundary cue, so the stay explanation remains possible
                // but loses against a matching successor.
                candidate.logWeight -= 0.45
            }
        } else {
            candidate.consecutiveUnexpectedAttacks = min(
                8,
                candidate.consecutiveUnexpectedAttacks + 1
            )
            candidate.logWeight -= Configuration.insertionPenalty
                + min(1.25, Double(candidate.consecutiveUnexpectedAttacks - 1) * 0.28)
            candidate.currentHasContradiction = true
        }

        if let elapsed = elapsed(from: source.lastAttackAt, to: attack.timestamp) {
            candidate.logWeight += timing.sameOnsetLogLikelihood(
                elapsedTicks: elapsed,
                attack: score.gestures[source.index].attack
            )
        }
        result.append(candidate)
    }

    private func appendSameOnsetHandInterpretations(
        _ source: Hypothesis,
        attack: PerformanceNoteAttack,
        bit: UInt128,
        to result: inout [Hypothesis]
    ) {
        for mode in EngravingHandMode.allCases where mode != source.mode {
            let expected = score.gestures[source.index].mask(for: mode)
            guard expected & bit != 0 else { continue }
            var candidate = source
            candidate.mode = mode
            candidate.observedMask |= bit
            candidate.unexpectedMask = candidate.observedMask & ~expected
            candidate.lastAttackAt = attack.timestamp ?? source.lastAttackAt
            candidate.currentHasContradiction = candidate.unexpectedMask != 0
            candidate.consecutiveUnexpectedAttacks = 0
            candidate.logWeight += 1.35 - Configuration.handModeChangePenalty
            result.append(candidate)
        }
    }

    private func appendLocalTransitions(
        _ source: Hypothesis,
        attack: PerformanceNoteAttack,
        bit: UInt128,
        to result: inout [Hypothesis]
    ) {
        let currentExpected = score.gestures[source.index].mask(for: source.mode)
        let pitchIsUnplayedCurrentNote = currentExpected & bit != 0
            && source.observedMask & bit == 0
        let coverage = Self.coverage(source.observedMask, expected: currentExpected)
        let closure = closurePenalty(for: source, expected: currentExpected)
        let interAttackInterval = elapsed(from: source.lastAttackAt, to: attack.timestamp)
        let sameOnsetSupport = attack.hadDepressedKeysBeforeAttack
            ? timing.sameOnsetSupport(
                elapsedTicks: interAttackInterval,
                attack: score.gestures[source.index].attack
            )
            : 0

        for newMode in EngravingHandMode.allCases {
            let successors = score.successors(
                of: source.index,
                mode: newMode,
                limit: Configuration.localDeletionDepth
            )
            for (skipCount, destination) in successors.enumerated() {
                if !source.isRestart, let committedIndex,
                   !isInLocalNeighborhood(destination, of: committedIndex) {
                    continue
                }
                let expected = score.gestures[destination].mask(for: newMode)
                guard expected != 0 else { continue }

                var candidate = source
                candidate.index = destination
                candidate.mode = newMode
                candidate.observedMask = bit
                candidate.unexpectedMask = expected & bit == 0 ? bit : 0
                candidate.onsetStartedAt = attack.timestamp
                candidate.lastAttackAt = attack.timestamp
                candidate.completedOnsetSpanTicks = elapsed(
                    from: source.onsetStartedAt,
                    to: source.lastAttackAt
                )
                candidate.completedOnsetAttack = score.gestures[source.index].attack
                candidate.episodeOnsets += 1
                candidate.coherentOnsets = source.currentHasContradiction
                    ? 1
                    : source.coherentOnsets + 1
                candidate.currentHasContradiction = expected & bit == 0
                candidate.consecutiveUnexpectedAttacks = expected & bit == 0 ? 1 : 0

                candidate.logWeight -= closure
                candidate.logWeight -= Double(skipCount) * Configuration.deletionPenalty
                candidate.logWeight -= newMode == source.mode
                    ? 0.12
                    : Configuration.handModeChangePenalty
                candidate.logWeight += expected & bit != 0 ? 1.70 : -1.45
                candidate.logWeight += source.clock.transitionLogLikelihood(
                    at: attack.timestamp,
                    beat: score.gestures[destination].beat
                )
                if attack.hadDepressedKeysBeforeAttack {
                    candidate.logWeight += timing.newOnsetLogLikelihood(
                        elapsedTicks: interAttackInterval,
                        precedingAttack: score.gestures[source.index].attack
                    )
                }

                if pitchIsUnplayedCurrentNote {
                    candidate.logWeight -= 0.45 + 1.75 * sameOnsetSupport
                } else if currentExpected & bit == 0,
                          EngravingHandMode.allCases.contains(where: {
                              score.gestures[source.index].mask(for: $0) & bit != 0
                          }) {
                    // A note from the other hand at this same score moment should not advance a
                    // one-hand path twice merely because the controller serialized the hands.
                    candidate.logWeight -= 1.2
                } else if currentExpected & bit != 0,
                          source.observedMask & bit != 0,
                          attack.wasReleasedSincePreviousAttack {
                    candidate.logWeight += 0.9
                } else if expected & bit != 0, currentExpected & bit == 0 {
                    candidate.logWeight += 0.45
                }
                if coverage >= 0.75 { candidate.logWeight += 0.25 }

                candidate.clock.observeTransition(
                    at: attack.timestamp,
                    beat: score.gestures[destination].beat
                )
                result.append(candidate)
            }
        }
    }

    private func appendIndexedSeeds(
        attack: PerformanceNoteAttack,
        bit: UInt128,
        restart: Bool,
        penalty: Double,
        to result: inout [Hypothesis]
    ) {
        for mode in EngravingHandMode.allCases {
            let lookup = score.candidateLookup(
                for: bit,
                mode: mode,
                limit: Configuration.candidatesPerMode,
                preferredRange: committedIndex == nil ? acquisitionRange : nil
            )
            for index in lookup.indices {
                if restart, let committedIndex,
                   isInLocalNeighborhood(index, of: committedIndex) { continue }
                let expected = score.gestures[index].mask(for: mode)
                var prior = -penalty + (expected & bit != 0 ? 1.65 : -1.45)
                if committedIndex == nil {
                    prior += score.acquisitionLogPrior(for: index, in: acquisitionRange)
                }
                if score.gestures[index].beginsMeasure { prior += 0.12 }

                var clock = timing.newClock()
                clock.beginEpisode(at: attack.timestamp, beat: score.gestures[index].beat)
                result.append(Hypothesis(
                    index: index,
                    mode: mode,
                    observedMask: bit,
                    unexpectedMask: expected & bit == 0 ? bit : 0,
                    onsetStartedAt: attack.timestamp,
                    lastAttackAt: attack.timestamp,
                    completedOnsetSpanTicks: nil,
                    completedOnsetAttack: nil,
                    logWeight: prior,
                    clock: clock,
                    isRestart: restart,
                    episodeStartIndex: index,
                    episodeOnsets: 1,
                    coherentOnsets: 1,
                    currentHasContradiction: expected & bit == 0,
                    consecutiveUnexpectedAttacks: expected & bit == 0 ? 1 : 0,
                    lookupIsExhaustive: lookup.isExhaustive,
                    preferredLookupIsExhaustive: lookup.preferredRangeIsExhaustive
                ))
            }
        }
    }

    /// Starts a clean local interpretation without turning ordinary recovery into a global jump.
    /// This branch is essential when a surviving hypothesis has assigned several mistakes to one
    /// onset: recovery must not depend on that contaminated onset eventually closing itself.
    private func appendLocalRecoverySeeds(
        attack: PerformanceNoteAttack,
        bit: UInt128,
        depth: Int,
        penalty: Double,
        to result: inout [Hypothesis]
    ) {
        guard let committedIndex else { return }
        for mode in EngravingHandMode.allCases {
            let destinations = [committedIndex]
                + score.successors(of: committedIndex, mode: mode, limit: depth)
            for destination in destinations {
                let expected = score.gestures[destination].mask(for: mode)
                guard expected & bit != 0 else { continue }
                let maximumBeatDistance = depth > Configuration.localNeighborhoodDepth
                    ? Configuration.lostRecoveryBeatDistance
                    : Configuration.localNeighborhoodBeatDistance
                guard score.gestures[destination].beat
                    - score.gestures[committedIndex].beat
                    <= maximumBeatDistance + EngravingReference.beatEpsilon else { continue }
                var clock = timing.newClock()
                clock.beginEpisode(at: attack.timestamp, beat: score.gestures[destination].beat)
                result.append(Hypothesis(
                    index: destination,
                    mode: mode,
                    observedMask: bit,
                    unexpectedMask: 0,
                    onsetStartedAt: attack.timestamp,
                    lastAttackAt: attack.timestamp,
                    completedOnsetSpanTicks: nil,
                    completedOnsetAttack: nil,
                    logWeight: -penalty + 1.45,
                    clock: clock,
                    isRestart: false,
                    episodeStartIndex: destination,
                    episodeOnsets: 1,
                    coherentOnsets: 1,
                    currentHasContradiction: false,
                    consecutiveUnexpectedAttacks: 0,
                    lookupIsExhaustive: true,
                    preferredLookupIsExhaustive: true
                ))
            }
        }
    }

    // MARK: - Commitment

    private mutating func commitAcquisitionIfReady() -> EngravingAlignmentResult? {
        let evidence = destinationEvidence(restart: false)
        guard let winner = strongestDestination(in: evidence) else { return nil }
        let runnerUp = evidence.values.map(\.mass).sorted(by: >).dropFirst().first ?? 0
        let hypothesis = hypotheses[winner.value.bestHypothesis]
        let confidence = winner.value.mass
        let margin = confidence - runnerUp
        let expected = score.gestures[hypothesis.index].mask(for: hypothesis.mode)
        let coverage = Self.coverage(hypothesis.observedMask, expected: expected)
        let distinctiveChord = expected.nonzeroBitCount >= 3
            && coverage >= 0.70
            && confidence >= 0.58
            && margin >= 0.14
        let isVisible = score.isVisible(hypothesis.index, in: acquisitionRange)
        let requiredOnsets = isVisible ? 2 : 3
        let minimumSequentialConfidence = hypothesis.lookupIsExhaustive ? 0.50 : 0.14
        let minimumSequentialMargin = hypothesis.lookupIsExhaustive
            ? 0.14
            : (isVisible ? 0.025 : 0.08)
        let sequential = hypothesis.coherentOnsets >= requiredOnsets
            && confidence >= minimumSequentialConfidence
            && margin >= minimumSequentialMargin
        let ambiguityResolved = hypothesis.lookupIsExhaustive
            || (isVisible
                && hypothesis.preferredLookupIsExhaustive
                && hypothesis.coherentOnsets >= 4
                && confidence >= 0.25
                && margin >= 0.025)
        guard ambiguityResolved, distinctiveChord || sequential else { return nil }

        committedIndex = hypothesis.index
        forwardFrontier = hypothesis.index
        weakEventStreak = 0
        lastState = .tracking
        updateParticipation(from: hypothesis)
        adoptTiming(from: hypothesis)
        retainCommittedBeam(around: hypothesis, fromRestart: false)
        let movement: EngravingAlignmentMovement = acquisitionRange != nil && !isVisible
            ? .jump
            : .held
        return makeResult(
            index: hypothesis.index,
            confidence: confidence,
            state: .tracking,
            movement: movement
        )
    }

    private mutating func publishTrackingResult(
        for attack: PerformanceNoteAttack,
        bit: UInt128
    ) -> EngravingAlignmentResult? {
        guard let oldIndex = committedIndex else { return nil }

        let restartEvidence = destinationEvidence(restart: true)
        if let relocation = readyRelocation(
            evidence: restartEvidence,
            from: oldIndex
        ) {
            let hypothesis = hypotheses[relocation.hypothesis]
            let isEarlier = hypothesis.index < (forwardFrontier ?? oldIndex)
            let movement: EngravingAlignmentMovement = isEarlier
                && score.isVisible(hypothesis.index, in: visibleRange) ? .replay : .jump
            committedIndex = hypothesis.index
            if movement == .jump { forwardFrontier = hypothesis.index }
            weakEventStreak = 0
            lastState = .tracking
            postReframeRecovery = movement == .jump ? 2 : postReframeRecovery
            updateParticipation(from: hypothesis)
            adoptTiming(from: hypothesis)
            retainCommittedBeam(around: hypothesis, fromRestart: true)
            return makeResult(
                index: hypothesis.index,
                confidence: relocation.confidence,
                state: .tracking,
                movement: movement
            )
        }

        let continuityEvidence = destinationEvidence(restart: false)
        let continuityMass = continuityEvidence.values.reduce(0) { $0 + $1.mass }
        let localMass = continuityEvidence.reduce(0.0) { partial, entry in
            partial + (isInLocalNeighborhood(entry.key, of: oldIndex) ? entry.value.mass : 0)
        }
        // Destination masses have already been normalized across continuity and restart classes.
        let localPosterior = localMass
        let supported = isSupportedLocally(bit: bit, from: oldIndex)

        if supported { weakEventStreak = 0 }
        else { weakEventStreak += 1 }

        var state: EngravingScoreFollower.TrackingState
        if weakEventStreak >= 3 || localPosterior < 0.18 {
            state = .lost
        } else if !supported || localPosterior < 0.56 {
            state = .uncertain
        } else {
            state = .tracking
        }

        if let winner = strongestDestination(in: continuityEvidence) {
            let hypothesis = hypotheses[winner.value.bestHypothesis]
            let conditionalConfidence = winner.value.mass / max(
                Double.leastNonzeroMagnitude,
                continuityMass
            )
            let isRecoverableForwardDestination = isInLocalNeighborhood(
                hypothesis.index,
                of: oldIndex
            ) || (lastState == .lost && isInLostRecoveryNeighborhood(
                hypothesis.index,
                of: oldIndex
            ))
            if hypothesis.index > oldIndex,
               isRecoverableForwardDestination,
               conditionalConfidence >= 0.36,
               hypothesis.observedMask
                   & score.gestures[hypothesis.index].mask(for: hypothesis.mode) != 0 {
                let immediate = score.successor(of: oldIndex, mode: hypothesis.mode)
                    == hypothesis.index
                committedIndex = hypothesis.index
                forwardFrontier = max(forwardFrontier ?? hypothesis.index, hypothesis.index)
                weakEventStreak = 0
                lastState = state
                if state == .tracking, postReframeRecovery > 0 { postReframeRecovery -= 1 }
                updateParticipation(from: hypothesis)
                adoptTiming(from: hypothesis)
                retainAfterForwardCommit(at: hypothesis.index)
                return makeResult(
                    index: hypothesis.index,
                    confidence: min(0.99, winner.value.mass),
                    state: state,
                    movement: immediate ? .continuous : .recovered
                )
            }
            if hypothesis.index == oldIndex, supported {
                updateParticipation(from: hypothesis)
            }
        }

        lastState = state
        return makeResult(
            index: oldIndex,
            confidence: min(
                0.99,
                max(0.01, continuityEvidence[oldIndex]?.mass ?? 0)
            ),
            state: state,
            movement: .held
        )
    }

    private func readyRelocation(
        evidence: [Int: DestinationEvidence],
        from incumbent: Int
    ) -> (hypothesis: Int, confidence: Double)? {
        guard let winner = strongestDestination(in: evidence) else { return nil }
        let restartMass = evidence.values.reduce(0) { $0 + $1.mass }
        let conditional = winner.value.mass / max(Double.leastNonzeroMagnitude, restartMass)
        let overall = winner.value.mass
        let runnerUp = evidence.values.map(\.mass).sorted(by: >).dropFirst().first ?? 0
        let margin = (winner.value.mass - runnerUp)
            / max(Double.leastNonzeroMagnitude, restartMass)
        let hypothesis = hypotheses[winner.value.bestHypothesis]
        let visibleReplay = hypothesis.index < (forwardFrontier ?? incumbent)
            && score.isVisible(hypothesis.index, in: visibleRange)
        let requiredOverall = visibleReplay ? 0.40 : 0.48
        let expected = score.gestures[hypothesis.index].mask(for: hypothesis.mode)
        return hypothesis.coherentOnsets >= 3
            && hypothesis.lookupIsExhaustive
            && conditional >= 0.62
            && margin >= 0.16
            && overall >= requiredOverall
            && Self.coverage(hypothesis.observedMask, expected: expected) >= 0.48
            ? (winner.value.bestHypothesis, min(0.99, overall))
            : nil
    }

    // MARK: - Probability management

    private func prune(_ candidates: [Hypothesis]) -> [Hypothesis] {
        guard !candidates.isEmpty else { return [] }
        var bestByState: [HypothesisKey: Hypothesis] = [:]
        bestByState.reserveCapacity(min(candidates.count, Configuration.beamWidth * 3))
        for candidate in candidates where candidate.logWeight.isFinite {
            let key = hypothesisKey(candidate)
            if let existing = bestByState[key] {
                if candidate.logWeight > existing.logWeight {
                    bestByState[key] = candidate
                }
            } else {
                bestByState[key] = candidate
            }
        }

        let unique = Array(bestByState.values)
        var ranked: [Hypothesis]
        if committedIndex == nil {
            let preferred = unique.filter {
                score.isVisible($0.index, in: acquisitionRange)
            }
            let scoreWide = unique.filter {
                !score.isVisible($0.index, in: acquisitionRange)
            }
            let preferredCapacity = acquisitionRange == nil
                ? 0
                : Configuration.beamWidth / 2
            ranked = selectDiverse(preferred, limit: preferredCapacity)
            ranked += selectDiverse(
                scoreWide,
                limit: Configuration.beamWidth - ranked.count
            )
            if ranked.count < Configuration.beamWidth {
                var selected = Set(ranked.map(hypothesisKey))
                let remainder = selectDiverse(unique, limit: Configuration.beamWidth).filter {
                    selected.insert(hypothesisKey($0)).inserted
                }
                ranked += remainder.prefix(Configuration.beamWidth - ranked.count)
            }
            ranked.sort(by: Self.hypothesisPrecedes)
        } else {
            ranked = selectDiverse(
                unique.filter { !$0.isRestart },
                limit: Configuration.continuityBeamWidth
            )
            ranked += selectDiverse(
                unique.filter(\.isRestart),
                limit: Configuration.beamWidth - Configuration.continuityBeamWidth
            )

            if ranked.count < Configuration.beamWidth {
                var selected = Set(ranked.map(hypothesisKey))
                let remainder = selectDiverse(unique, limit: Configuration.beamWidth).filter {
                    selected.insert(hypothesisKey($0)).inserted
                }
                ranked += remainder.prefix(Configuration.beamWidth - ranked.count)
            }
            ranked.sort(by: Self.hypothesisPrecedes)
        }

        // Lookup exhaustiveness is only meaningful if destination-diverse beam pruning also kept
        // every retrieved destination. Otherwise beam capacity itself could manufacture a unique
        // acquisition or relocation winner.
        if committedIndex == nil {
            let allDestinations = Set(unique.map(\.index))
            let retainedDestinations = Set(ranked.map(\.index))
            if retainedDestinations.count < allDestinations.count {
                for index in ranked.indices { ranked[index].lookupIsExhaustive = false }
            }

            let allPreferredDestinations = Set(unique.compactMap { hypothesis in
                score.isVisible(hypothesis.index, in: acquisitionRange)
                    ? hypothesis.index
                    : nil
            })
            let retainedPreferredDestinations = Set(ranked.compactMap { hypothesis in
                score.isVisible(hypothesis.index, in: acquisitionRange)
                    ? hypothesis.index
                    : nil
            })
            if retainedPreferredDestinations.count < allPreferredDestinations.count {
                for index in ranked.indices {
                    ranked[index].preferredLookupIsExhaustive = false
                }
            }
        } else {
            let allRestartDestinations = Set(unique.lazy.filter(\.isRestart).map(\.index))
            let retainedRestartDestinations = Set(ranked.lazy.filter(\.isRestart).map(\.index))
            if retainedRestartDestinations.count < allRestartDestinations.count {
                for index in ranked.indices where ranked[index].isRestart {
                    ranked[index].lookupIsExhaustive = false
                }
            }
        }
        if let maximum = ranked.first?.logWeight {
            for index in ranked.indices { ranked[index].logWeight -= maximum }
        }
        return ranked
    }

    private func selectDiverse(_ candidates: [Hypothesis], limit: Int) -> [Hypothesis] {
        guard limit > 0, !candidates.isEmpty else { return [] }
        let ordered = candidates.sorted(by: Self.hypothesisPrecedes)
        var counts: [DestinationClassKey: Int] = [:]
        counts.reserveCapacity(min(ordered.count, limit))
        var representatives: [Hypothesis] = []
        var alternatives: [Hypothesis] = []
        representatives.reserveCapacity(min(ordered.count, limit))
        alternatives.reserveCapacity(min(ordered.count, limit))
        for candidate in ordered {
            let key = DestinationClassKey(index: candidate.index, isRestart: candidate.isRestart)
            let count = counts[key, default: 0]
            guard count < Configuration.statesPerDestination else { continue }
            counts[key] = count + 1
            if count == 0 {
                representatives.append(candidate)
            } else {
                alternatives.append(candidate)
            }
        }

        if representatives.count >= limit { return Array(representatives.prefix(limit)) }
        var selected = representatives
        selected += alternatives.prefix(limit - selected.count)
        return selected
    }

    private func hypothesisKey(_ candidate: Hypothesis) -> HypothesisKey {
        HypothesisKey(
            index: candidate.index,
            mode: candidate.mode,
            observedMask: candidate.observedMask,
            isRestart: candidate.isRestart,
            episodeStartIndex: candidate.episodeStartIndex,
            episodeOnsets: candidate.episodeOnsets,
            coherentOnsets: candidate.coherentOnsets,
            currentHasContradiction: candidate.currentHasContradiction,
            consecutiveUnexpectedAttacks: candidate.consecutiveUnexpectedAttacks,
            onsetStartedAt: candidate.onsetStartedAt,
            lastAttackAt: candidate.lastAttackAt,
            completedOnsetSpanTicks: candidate.completedOnsetSpanTicks,
            completedOnsetAttack: candidate.completedOnsetAttack,
            clockLogTicksPerBeat: candidate.clock.logTicksPerBeat,
            clockLogDeviation: candidate.clock.logDeviation,
            clockSampleCount: candidate.clock.sampleCount,
            clockLastTimestamp: candidate.clock.lastTimestamp,
            clockLastBeat: candidate.clock.lastBeat,
            lookupIsExhaustive: candidate.lookupIsExhaustive,
            preferredLookupIsExhaustive: candidate.preferredLookupIsExhaustive
        )
    }

    private func destinationEvidence(restart: Bool) -> [Int: DestinationEvidence] {
        var evidence: [Int: DestinationEvidence] = [:]
        for (offset, hypothesis) in hypotheses.enumerated() where hypothesis.isRestart == restart {
            var item = evidence[hypothesis.index] ?? DestinationEvidence(
                bestHypothesis: offset,
                bestWeight: hypothesis.logWeight
            )
            if hypothesis.logWeight > item.bestWeight {
                item.bestWeight = hypothesis.logWeight
                item.bestHypothesis = offset
            }
            evidence[hypothesis.index] = item
        }

        let classWeights = destinationClassLogWeights()
        let logDenominator = Self.logSumExp(Array(classWeights.values))
        for index in evidence.keys {
            guard var item = evidence[index] else { continue }
            let key = DestinationClassKey(index: index, isRestart: restart)
            guard let classWeight = classWeights[key] else { continue }
            item.mass = Foundation.exp(classWeight - logDenominator)
            evidence[index] = item
        }
        return evidence
    }

    /// Marginalizes the mutually exclusive hand interpretations while using the best retained
    /// onset-history representative within each hand. This prevents branch multiplicity from
    /// manufacturing confidence while still giving hand uncertainty a normalized prior.
    private func destinationClassLogWeights() -> [DestinationClassKey: Double] {
        var bestByMode: [DestinationClassKey: [EngravingHandMode: Double]] = [:]
        for hypothesis in hypotheses {
            let key = DestinationClassKey(
                index: hypothesis.index,
                isRestart: hypothesis.isRestart
            )
            bestByMode[key, default: [:]][hypothesis.mode] = max(
                bestByMode[key]?[hypothesis.mode] ?? -.infinity,
                hypothesis.logWeight
            )
        }
        let modePrior = Foundation.log(Double(EngravingHandMode.allCases.count))
        return bestByMode.mapValues { scores in
            Self.logSumExp(Array(scores.values)) - modePrior
        }
    }

    private func strongestDestination(
        in evidence: [Int: DestinationEvidence]
    ) -> (key: Int, value: DestinationEvidence)? {
        let ranked = evidence.sorted {
            if $0.value.mass != $1.value.mass { return $0.value.mass > $1.value.mass }
            return $0.key < $1.key
        }
        guard let winner = ranked.first else { return nil }
        if let runnerUp = ranked.dropFirst().first,
           abs(winner.value.mass - runnerUp.value.mass) <= 1e-12 {
            return nil
        }
        return winner
    }

    private func bestContinuityClock() -> PerformanceTempoTracker? {
        hypotheses.first(where: { !$0.isRestart })?.clock
    }

    private mutating func retainAfterForwardCommit(at index: Int) {
        hypotheses.removeAll { !$0.isRestart && $0.index != index }
        hypotheses = prune(hypotheses)
    }

    // MARK: - Evidence helpers

    private func closurePenalty(for hypothesis: Hypothesis, expected: UInt128) -> Double {
        let missing = (expected & ~hypothesis.observedMask).nonzeroBitCount
        let unexpected = hypothesis.unexpectedMask.nonzeroBitCount
        return min(
            Configuration.maximumClosurePenalty,
            Double(missing) * Configuration.missingNotePenalty
                + Double(unexpected) * 0.22
        )
    }

    private func isSupportedLocally(bit: UInt128, from index: Int) -> Bool {
        for mode in EngravingHandMode.allCases {
            if score.gestures[index].mask(for: mode) & bit != 0 { return true }
            if let next = score.successor(of: index, mode: mode),
               score.gestures[next].mask(for: mode) & bit != 0 { return true }
        }
        return false
    }

    private func isInLocalNeighborhood(_ candidate: Int, of origin: Int) -> Bool {
        isInForwardNeighborhood(
            candidate,
            of: origin,
            depth: Configuration.localNeighborhoodDepth,
            maximumBeatDistance: Configuration.localNeighborhoodBeatDistance
        )
    }

    private func isInLostRecoveryNeighborhood(_ candidate: Int, of origin: Int) -> Bool {
        isInForwardNeighborhood(
            candidate,
            of: origin,
            depth: Configuration.lostRecoveryDepth,
            maximumBeatDistance: Configuration.lostRecoveryBeatDistance
        )
    }

    private func isInForwardNeighborhood(
        _ candidate: Int,
        of origin: Int,
        depth: Int,
        maximumBeatDistance: Double
    ) -> Bool {
        if candidate == origin { return true }
        for mode in EngravingHandMode.allCases {
            var cursor = origin
            for _ in 0..<depth {
                guard let next = score.successor(of: cursor, mode: mode) else { break }
                if score.gestures[next].beat - score.gestures[origin].beat
                    > maximumBeatDistance + EngravingReference.beatEpsilon { break }
                if next == candidate { return true }
                cursor = next
            }
        }
        return false
    }

    private mutating func updateParticipation(from hypothesis: Hypothesis) {
        leftEvidence *= 0.84
        rightEvidence *= 0.84
        switch hypothesis.mode {
        case .both:
            let gesture = score.gestures[hypothesis.index]
            if gesture.mask(for: .left) & hypothesis.observedMask != 0 { leftEvidence += 1 }
            if gesture.mask(for: .right) & hypothesis.observedMask != 0 { rightEvidence += 1 }
        case .left:
            leftEvidence += 1
        case .right:
            rightEvidence += 1
        }

        let weaker = min(leftEvidence, rightEvidence)
        let stronger = max(leftEvidence, rightEvidence)
        if weaker >= 1.25, stronger / max(0.001, weaker) < 2.6 {
            participation = .both
        } else if leftEvidence >= 1.6, leftEvidence > rightEvidence * 2.4 {
            participation = .left
        } else if rightEvidence >= 1.6, rightEvidence > leftEvidence * 2.4 {
            participation = .right
        }
    }

    private mutating func adoptTiming(from hypothesis: Hypothesis) {
        timing.adopt(hypothesis.clock)
        if let ticks = hypothesis.completedOnsetSpanTicks,
           let attack = hypothesis.completedOnsetAttack {
            timing.observeOnsetSpan(ticks: ticks, attack: attack)
        }
    }

    private func makeResult(
        index: Int,
        confidence: Double,
        state: EngravingScoreFollower.TrackingState,
        movement: EngravingAlignmentMovement
    ) -> EngravingAlignmentResult {
        EngravingAlignmentResult(
            gestureIndex: index,
            confidence: confidence,
            state: state,
            activeHands: participation,
            movement: movement
        )
    }

    private mutating func retainCommittedBeam(
        around winner: Hypothesis,
        fromRestart: Bool
    ) {
        let cutoff = winner.logWeight - 6
        hypotheses = hypotheses.compactMap { candidate in
            guard candidate.isRestart == fromRestart,
                  candidate.logWeight >= cutoff,
                  candidate.index == winner.index else {
                return nil
            }
            var retained = candidate
            retained.isRestart = false
            return retained
        }
        if hypotheses.isEmpty {
            var retained = winner
            retained.isRestart = false
            hypotheses = [retained]
        }
        hypotheses = prune(hypotheses)
    }

    private mutating func resetPosition(acquisitionRange: ClosedRange<Double>?) {
        hypotheses.removeAll(keepingCapacity: true)
        self.acquisitionRange = acquisitionRange
        visibleRange = acquisitionRange
        committedIndex = nil
        forwardFrontier = nil
        lastState = .uncertain
        weakEventStreak = 0
        postReframeRecovery = 0
        leftEvidence = 0
        rightEvidence = 0
        participation = .unknown
    }

    private static func coverage(_ observed: UInt128, expected: UInt128) -> Double {
        guard expected != 0 else { return 0 }
        return Double((observed & expected).nonzeroBitCount) / Double(expected.nonzeroBitCount)
    }

    private static func logSumExp(_ values: [Double]) -> Double {
        guard let maximum = values.max(), maximum.isFinite else { return -.infinity }
        return maximum + Foundation.log(values.reduce(0) {
            $0 + Foundation.exp($1 - maximum)
        })
    }

    private static func hypothesisPrecedes(_ lhs: Hypothesis, _ rhs: Hypothesis) -> Bool {
        if lhs.logWeight != rhs.logWeight { return lhs.logWeight > rhs.logWeight }
        if lhs.isRestart != rhs.isRestart { return !lhs.isRestart }
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        if lhs.mode.rawValue != rhs.mode.rawValue { return lhs.mode.rawValue < rhs.mode.rawValue }
        return lhs.episodeStartIndex < rhs.episodeStartIndex
    }

    private func elapsed(
        from start: MIDITimeStamp?,
        to end: MIDITimeStamp?
    ) -> Double? {
        guard let start, let end, end > start else { return nil }
        return Double(end - start)
    }
}
