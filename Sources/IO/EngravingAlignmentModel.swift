//
//  EngravingAlignmentModel.swift
//  MIDIKit
//

import Foundation


enum EngravingAlignmentMovement {
    case held
    case continuous
    case correction
    case replay
    case jump
}

struct EngravingAlignmentResult {
    let gestureIndex: Int
    let plausibleIndices: [Int]
    let confidence: Double
    let state: EngravingScoreFollower.TrackingState
    let activeHands: EngravingScoreFollower.HandParticipation
    let movement: EngravingAlignmentMovement
}

/// Gesture-level online alignment with one monotone local incumbent and bounded global
/// challengers. Replay and jump are classifications of a winning challenger, not independent
/// state machines.
struct EngravingAlignmentModel {
    private enum Configuration {
        static let acquisitionCandidatesPerMode = 18
        static let challengerSeedsPerMode = 12
        static let challengerBeamWidth = 28
        static let minimumLocalMatch = 0.58
        static let localAdvanceMargin = 0.35
        static let deletionPenalty = 2.7
        static let insertionPenalty = 0.7
        static let restartPenalty = 0.65
        static let jumpEvidence = 3.0
        static let replayEvidence = 4.1
        static let maximumHistory = 5
        static let provisionalTailLength = 3
    }

    private struct AcquisitionCandidate: Hashable {
        let index: Int
        let mode: EngravingHandMode
        let score: Double

        func hash(into hasher: inout Hasher) {
            hasher.combine(index)
            hasher.combine(mode)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.index == rhs.index && lhs.mode == rhs.mode
        }
    }

    private struct ChallengerKey: Hashable {
        let index: Int
        let mode: EngravingHandMode
        let seedIndex: Int
    }

    private struct Challenger {
        var index: Int
        let mode: EngravingHandMode
        let seedIndex: Int
        var completedEvidence: Double
        var currentEvidence: Double
        var qualityTotal: Double
        var currentQuality: Double
        var completedDistinguishingCount: Int
        var age: Int
        var clock: PerformanceTempoTracker

        var evidence: Double { completedEvidence + currentEvidence }
        var averageQuality: Double {
            (qualityTotal + currentQuality) / Double(max(1, age))
        }
        var distinguishingCount: Int {
            completedDistinguishingCount + (currentEvidence >= 0.75 ? 1 : 0)
        }
    }

    private struct PendingSkip {
        let target: Int
        let mode: EngravingHandMode
    }

    let score: EngravingScoreFeatureIndex

    private(set) var currentIndex: Int?
    private var currentMode: EngravingHandMode = .both
    private var forwardFrontier: Int?
    private var acquisitionRange: ClosedRange<Double>?
    private var visibleRange: ClosedRange<Double>?
    private var previousCompletedGesture: PerformanceGesture?
    private var history: [PerformanceGesture] = []
    private var isTracking = false
    private var localMismatchStreak = 0
    private var currentGestureIsNew = false
    /// Once true, later note-ons can refine this chord but cannot consume another score moment.
    private var hasAlignedCurrentGesture = false
    private var transitionOriginIndex: Int?
    private var assemblyExpectationIndex: Int?
    private var pendingSkip: PendingSkip?
    private var challengers: [Challenger] = []
    private var provisionalLocalIndices: [Int] = []
    private var leftEvidence = 0.0
    private var rightEvidence = 0.0
    private var currentLeftEvidence = 0.0
    private var currentRightEvidence = 0.0
    private var participation: EngravingScoreFollower.HandParticipation = .unknown
    private var timing = PerformanceTimingModel()

    init(score: EngravingScoreFeatureIndex) {
        self.score = score
    }

    mutating func reset(acquisitionRange: ClosedRange<Double>?) {
        currentIndex = nil
        currentMode = .both
        forwardFrontier = nil
        self.acquisitionRange = acquisitionRange
        visibleRange = nil
        previousCompletedGesture = nil
        history.removeAll(keepingCapacity: true)
        isTracking = false
        localMismatchStreak = 0
        currentGestureIsNew = false
        hasAlignedCurrentGesture = false
        transitionOriginIndex = nil
        assemblyExpectationIndex = nil
        pendingSkip = nil
        challengers.removeAll(keepingCapacity: true)
        provisionalLocalIndices.removeAll(keepingCapacity: true)
        leftEvidence = 0
        rightEvidence = 0
        currentLeftEvidence = 0
        currentRightEvidence = 0
        participation = .unknown
        timing.reset()
    }

    mutating func setVisibleRange(_ range: ClosedRange<Double>?) {
        visibleRange = range
    }

    var gestureContext: PerformanceGestureContext {
        guard let currentIndex else { return .unknown }
        let expectedIndex = assemblyExpectationIndex ?? currentIndex
        var currentMasks = score.gestures[expectedIndex].masks
        var attack = score.gestures[expectedIndex].attack

        // A newly seeded challenger contributes only chord-membership information. It cannot
        // move the incumbent, but prevents a serialized remote chord from being split into one
        // gesture per MIDI note while its destination is still under evaluation.
        for challenger in challengers.prefix(6)
        where challenger.currentEvidence > 0.9
            && challenger.currentQuality > 0.5
            && score.gestures.indices.contains(challenger.index) {
            let gesture = score.gestures[challenger.index]
            for mode in EngravingHandMode.allCases {
                currentMasks[mode] |= gesture.mask(for: mode)
            }
            if gesture.attack == .rolled { attack = .rolled }
        }

        var nextMasks = EngravingPitchMasks()
        for mode in EngravingHandMode.allCases {
            if let next = score.successor(of: expectedIndex, mode: mode) {
                nextMasks[mode] = score.gestures[next].mask(for: mode)
            }
        }
        return PerformanceGestureContext(
            currentMasks: currentMasks,
            nextMasks: nextMasks,
            attack: attack,
            timing: timing.gestureHint(for: attack)
        )
    }

    mutating func consume(_ change: PerformanceGestureChange) -> EngravingAlignmentResult? {
        switch change {
        case let .began(observation):
            currentGestureIsNew = true
            hasAlignedCurrentGesture = false
            return acquireOrUpdate(with: observation, previous: nil)

        case let .extended(observation):
            if !isTracking {
                return acquireOrUpdate(with: observation, previous: previousCompletedGesture)
            }
            return updateCurrentGesture(observation)

        case let .crossedBoundary(completed, current):
            if let currentIndex {
                let gesture = score.gestures[currentIndex]
                timing.observeCompletedGesture(
                    completed,
                    attack: gesture.attack,
                    expectedDurationBeats: gesture.duration(for: currentMode),
                    matchQuality: matchQuality(completed, at: currentIndex, mode: currentMode)
                )
            }
            finalizeParticipationGesture()
            previousCompletedGesture = completed
            history.append(completed)
            if history.count > Configuration.maximumHistory {
                history.removeFirst(history.count - Configuration.maximumHistory)
            }
            currentGestureIsNew = true
            hasAlignedCurrentGesture = false
            if !isTracking {
                return acquireOrUpdate(with: current, previous: completed)
            }
            transitionOriginIndex = currentIndex
            if let currentIndex {
                assemblyExpectationIndex = score.successor(of: currentIndex, mode: currentMode)
                    ?? currentIndex
            }
            return alignNewGesture(current)
        }
    }

    // MARK: Acquisition

    private mutating func acquireOrUpdate(
        with observation: PerformanceGesture,
        previous: PerformanceGesture?
    ) -> EngravingAlignmentResult? {
        let candidates = acquisitionCandidates(observation: observation, previous: previous)
        guard let best = candidates.first else { return nil }
        let oldIndex = currentIndex
        currentIndex = best.index
        currentMode = best.mode
        assemblyExpectationIndex = best.index
        forwardFrontier = max(forwardFrontier ?? best.index, best.index)
        updateParticipation(mode: best.mode, quality: matchQuality(observation, at: best.index, mode: best.mode))

        let scoreGesture = score.gestures[best.index]
        let completeChord = observation.pitchMask.nonzeroBitCount > 1
            && matchQuality(observation, at: best.index, mode: best.mode) >= 0.96
            && (best.mode == .both
                || scoreGesture.mask(for: best.mode) == scoreGesture.mask(for: .both))
        if previous != nil || completeChord {
            isTracking = true
            transitionOriginIndex = best.index
            provisionalLocalIndices = [best.index]
            hasAlignedCurrentGesture = true
            timing.anchorLocal(at: observation.startedAt, beat: score.gestures[best.index].beat)
        }

        let margin = candidates.count > 1 ? best.score - candidates[1].score : 4
        let confidence = Self.logistic(margin / 1.6)
        let movement: EngravingAlignmentMovement
        if let oldIndex, oldIndex != best.index, previous != nil {
            movement = abs(best.index - oldIndex) > 2 ? .jump : .continuous
        } else {
            movement = .held
        }
        return result(
            index: best.index,
            confidence: confidence,
            state: isTracking ? .tracking : .acquiring,
            movement: movement,
            alternatives: candidates.prefix(5).map(\.index)
        )
    }

    private func acquisitionCandidates(
        observation: PerformanceGesture,
        previous: PerformanceGesture?
    ) -> [AcquisitionCandidate] {
        var best: [AcquisitionCandidate: AcquisitionCandidate] = [:]
        best.reserveCapacity(Configuration.acquisitionCandidatesPerMode * 3)

        for mode in EngravingHandMode.allCases {
            let indices = score.candidateIndices(
                for: observation.pitchMask,
                previousMask: previous?.pitchMask,
                mode: mode,
                limit: Configuration.acquisitionCandidatesPerMode
            )
            for index in indices {
                let currentQuality = matchQuality(observation, at: index, mode: mode)
                var value = currentQuality * 6
                if let previous,
                   let predecessor = predecessor(of: index, mode: mode) {
                    value += matchQuality(previous, at: predecessor, mode: mode) * 5
                    value += transitionAgreement(
                        previous: previous,
                        current: observation,
                        destination: index
                    )
                }
                if let acquisitionRange,
                   score.isVisible(index, in: acquisitionRange) {
                    value += 2.6
                }
                if mode == .both { value += 0.1 }
                let candidate = AcquisitionCandidate(index: index, mode: mode, score: value)
                if best[candidate]?.score ?? -.infinity < value { best[candidate] = candidate }
            }
        }
        return best.values.sorted {
            $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score
        }
    }

    // MARK: Local incumbent

    private mutating func alignNewGesture(_ observation: PerformanceGesture) -> EngravingAlignmentResult {
        guard let origin = transitionOriginIndex ?? currentIndex else {
            return result(index: 0, confidence: 0, state: .lost, movement: .held, alternatives: [])
        }

        if let pendingSkip,
           let successor = score.successor(of: pendingSkip.target, mode: pendingSkip.mode),
           matchQuality(observation, at: successor, mode: pendingSkip.mode) >= 0.68 {
            self.pendingSkip = nil
            return commitLocal(
                index: successor,
                mode: pendingSkip.mode,
                quality: matchQuality(observation, at: successor, mode: pendingSkip.mode),
                observation: observation
            )
        }

        updateChallengers(observation, localOrigin: origin, beginsNewGesture: true)
        if let committed = commitWinningChallengerIfReady(observation: observation) {
            return committed
        }
        return evaluateLocal(observation, origin: origin)
    }

    private mutating func updateCurrentGesture(_ observation: PerformanceGesture) -> EngravingAlignmentResult {
        guard let origin = transitionOriginIndex ?? currentIndex else {
            return result(index: 0, confidence: 0, state: .lost, movement: .held, alternatives: [])
        }
        updateChallengers(observation, localOrigin: origin, beginsNewGesture: false)
        if let committed = commitWinningChallengerIfReady(observation: observation) {
            return committed
        }
        return evaluateLocal(observation, origin: origin)
    }

    private mutating func evaluateLocal(
        _ observation: PerformanceGesture,
        origin: Int
    ) -> EngravingAlignmentResult {
        let holdQuality = matchQuality(observation, at: origin, mode: currentMode)
        let holdScore = holdQuality * 5 - Configuration.insertionPenalty
        var bestIndex = origin
        var bestMode = currentMode
        var bestQuality = holdQuality
        var bestScore = holdScore
        let insertionRecoveryEvidence: Double
        if let previousCompletedGesture,
           matchQuality(previousCompletedGesture, at: origin, mode: currentMode) < 0.45 {
            insertionRecoveryEvidence = timing.mistakeEvidence(
                for: previousCompletedGesture,
                expectedDurationBeats: score.gestures[origin].duration(for: currentMode)
            )
        } else {
            insertionRecoveryEvidence = 0
        }

        for mode in EngravingHandMode.allCases {
            let modeChangePenalty = mode == currentMode ? 0 : 0.3
            let modeHoldQuality = matchQuality(observation, at: origin, mode: mode)
            let modeHoldScore = modeHoldQuality * 5 - modeChangePenalty
            if modeHoldScore > bestScore {
                bestMode = mode
                bestQuality = modeHoldQuality
                bestScore = modeHoldScore
            }

            // A physical gesture that has already consumed one score position is structurally
            // unable to consume another, regardless of how well a later chord tone matches it.
            if hasAlignedCurrentGesture { continue }
            guard let next = score.successor(of: origin, mode: mode) else { continue }
            let quality = matchQuality(observation, at: next, mode: mode)
            let candidateScore = quality * 5 + 0.55 - modeChangePenalty
                + insertionRecoveryEvidence
                + timing.localTransitionScore(
                    at: observation.startedAt,
                    beat: score.gestures[next].beat
                )
            if quality >= Configuration.minimumLocalMatch,
               candidateScore >= bestScore + Configuration.localAdvanceMargin {
                bestIndex = next
                bestMode = mode
                bestQuality = quality
                bestScore = candidateScore
            }

            if let second = score.successor(of: next, mode: mode) {
                let skipQuality = matchQuality(observation, at: second, mode: mode)
                let skipScore = skipQuality * 5 - Configuration.deletionPenalty
                    + timing.localTransitionScore(
                        at: observation.startedAt,
                        beat: score.gestures[second].beat
                    )
                if skipQuality >= 0.82, skipScore > bestScore {
                    pendingSkip = PendingSkip(target: second, mode: mode)
                }
            }
        }

        if bestIndex != origin {
            return commitLocal(
                index: bestIndex,
                mode: bestMode,
                quality: bestQuality,
                observation: observation
            )
        }

        currentMode = bestMode
        if hasAlignedCurrentGesture {
            updateParticipation(mode: bestMode, quality: bestQuality)
        }
        let strongestChallenger = challengers.max { $0.evidence < $1.evidence }
        localMismatchStreak = bestQuality < 0.38 ? localMismatchStreak + (currentGestureIsNew ? 1 : 0) : 0
        currentGestureIsNew = false
        assemblyExpectationIndex = hasAlignedCurrentGesture
            ? origin
            : (score.successor(of: origin, mode: currentMode) ?? origin)
        let uncertain = holdQuality < 0.5 || (strongestChallenger?.evidence ?? 0) > 1.25
        let state: EngravingScoreFollower.TrackingState = localMismatchStreak >= 3 ? .lost : (uncertain ? .uncertain : .tracking)
        let confidence = max(0.05, min(0.88, holdQuality * 0.75 + (uncertain ? 0.05 : 0.2)))
        return result(
            index: currentIndex ?? origin,
            confidence: confidence,
            state: state,
            movement: .held,
            alternatives: alternativeIndices(including: origin)
        )
    }

    private mutating func commitLocal(
        index: Int,
        mode: EngravingHandMode,
        quality: Double,
        observation: PerformanceGesture
    ) -> EngravingAlignmentResult {
        timing.observeLocalTransition(
            at: observation.startedAt,
            beat: score.gestures[index].beat
        )
        currentIndex = index
        currentMode = mode
        forwardFrontier = max(forwardFrontier ?? index, index)
        assemblyExpectationIndex = index
        transitionOriginIndex = index
        pendingSkip = nil
        localMismatchStreak = 0
        currentGestureIsNew = false
        hasAlignedCurrentGesture = true
        recordProvisional(index)
        updateParticipation(mode: mode, quality: quality)
        return result(
            index: index,
            confidence: min(0.98, 0.48 + quality * 0.5),
            state: .tracking,
            movement: .continuous,
            alternatives: alternativeIndices(including: index)
        )
    }

    // MARK: Global challengers

    private mutating func updateChallengers(
        _ observation: PerformanceGesture,
        localOrigin: Int,
        beginsNewGesture: Bool
    ) {
        let localExpected = expectedLocalIndex(for: observation, from: localOrigin)
        var updated: [Challenger] = []
        updated.reserveCapacity(Configuration.challengerBeamWidth * 2)

        for var challenger in challengers {
            var transitionTimingEvidence = 0.0
            if beginsNewGesture {
                guard let next = score.successor(of: challenger.index, mode: challenger.mode) else {
                    continue
                }
                challenger.completedEvidence += challenger.currentEvidence
                challenger.qualityTotal += challenger.currentQuality
                if challenger.currentEvidence >= 0.75 {
                    challenger.completedDistinguishingCount += 1
                }
                challenger.currentEvidence = 0
                challenger.currentQuality = 0
                challenger.index = next
                challenger.age += 1
                transitionTimingEvidence = challenger.clock.compatibility(
                    at: observation.startedAt,
                    beat: score.gestures[next].beat
                )
            }
            let evidence = relativeEvidence(
                observation,
                challengerIndex: challenger.index,
                challengerMode: challenger.mode,
                localIndex: localExpected,
                localMode: currentMode
            )
            challenger.currentEvidence = evidence + transitionTimingEvidence * 0.45
            challenger.currentQuality = matchQuality(
                observation,
                at: challenger.index,
                mode: challenger.mode
            )
            if beginsNewGesture, challenger.currentQuality >= 0.5 {
                challenger.clock.observe(
                    at: observation.startedAt,
                    beat: score.gestures[challenger.index].beat
                )
            }
            if challenger.currentQuality >= 0.28 || challenger.evidence > 0 {
                updated.append(challenger)
            }
        }

        for mode in EngravingHandMode.allCases {
            let indices = score.candidateIndices(
                for: observation.pitchMask,
                previousMask: nil,
                mode: mode,
                limit: Configuration.challengerSeedsPerMode
            )
            for index in indices {
                if abs(index - localOrigin) <= 2 { continue }
                let quality = matchQuality(observation, at: index, mode: mode)
                guard quality >= 0.42 else { continue }
                var clock = PerformanceTempoTracker()
                clock.reset(at: observation.startedAt, beat: score.gestures[index].beat)
                updated.append(Challenger(
                    index: index,
                    mode: mode,
                    seedIndex: index,
                    completedEvidence: -Configuration.restartPenalty,
                    currentEvidence: relativeEvidence(
                        observation,
                        challengerIndex: index,
                        challengerMode: mode,
                        localIndex: localExpected,
                        localMode: currentMode
                    ),
                    qualityTotal: 0,
                    currentQuality: quality,
                    completedDistinguishingCount: 0,
                    age: 1,
                    clock: clock
                ))
            }
        }

        var bestByState: [ChallengerKey: Challenger] = [:]
        bestByState.reserveCapacity(updated.count)
        for candidate in updated {
            let key = ChallengerKey(
                index: candidate.index,
                mode: candidate.mode,
                seedIndex: candidate.seedIndex
            )
            if bestByState[key]?.evidence ?? -.infinity < candidate.evidence {
                bestByState[key] = candidate
            }
        }
        challengers = bestByState.values.sorted {
            if $0.evidence != $1.evidence { return $0.evidence > $1.evidence }
            if $0.averageQuality != $1.averageQuality { return $0.averageQuality > $1.averageQuality }
            return $0.index < $1.index
        }
        if challengers.count > Configuration.challengerBeamWidth {
            challengers.removeLast(challengers.count - Configuration.challengerBeamWidth)
        }
    }

    private mutating func commitWinningChallengerIfReady(
        observation: PerformanceGesture
    ) -> EngravingAlignmentResult? {
        guard let incumbent = currentIndex, let best = challengers.first else { return nil }
        let destinationVisible = score.isVisible(best.index, in: visibleRange)
        let isEarlier = best.index < (forwardFrontier ?? incumbent)
        let requiredAge = isEarlier && destinationVisible ? 3 : 2
        let requiredEvidence = isEarlier && destinationVisible
            ? Configuration.replayEvidence
            : Configuration.jumpEvidence
        guard best.age >= requiredAge,
              best.distinguishingCount >= 2,
              best.evidence >= requiredEvidence,
              best.averageQuality >= 0.62 else { return nil }

        let movement: EngravingAlignmentMovement
        if provisionalLocalIndices.contains(best.index) {
            movement = .correction
        } else if isEarlier && destinationVisible {
            movement = .replay
        } else {
            movement = .jump
        }

        currentIndex = best.index
        currentMode = best.mode
        if movement != .replay && movement != .correction {
            forwardFrontier = best.index
            provisionalLocalIndices.removeAll(keepingCapacity: true)
        }
        assemblyExpectationIndex = best.index
        transitionOriginIndex = best.index
        pendingSkip = nil
        challengers.removeAll(keepingCapacity: true)
        localMismatchStreak = 0
        currentGestureIsNew = false
        hasAlignedCurrentGesture = true
        timing.adopt(best.clock)
        updateParticipation(mode: best.mode, quality: best.currentQuality)
        recordProvisional(best.index)

        return result(
            index: best.index,
            confidence: min(0.99, 0.68 + best.averageQuality * 0.28),
            state: .tracking,
            movement: movement,
            alternatives: [best.index]
        )
    }

    /// Scores only evidence that distinguishes the two locations. Shared notes are neutral.
    private func relativeEvidence(
        _ observation: PerformanceGesture,
        challengerIndex: Int,
        challengerMode: EngravingHandMode,
        localIndex: Int,
        localMode: EngravingHandMode
    ) -> Double {
        let observed = observation.pitchMask
        let challenger = score.gestures[challengerIndex].mask(for: challengerMode)
        let local = score.gestures[localIndex].mask(for: localMode)
        let challengerOnly = challenger & ~local
        let localOnly = local & ~challenger
        let challengerHits = (observed & challengerOnly).nonzeroBitCount
        let localHits = (observed & localOnly).nonzeroBitCount

        var evidence = Double(challengerHits - localHits) * 1.25
        let challengerQuality = EngravingScoreFeatureIndex.pitchSimilarity(observed, challenger)
        let localQuality = EngravingScoreFeatureIndex.pitchSimilarity(observed, local)
        evidence += (challengerQuality - localQuality) * 2.8

        // Missing candidate-relative notes are considered only for observations coherent enough
        // to represent a resolved gesture. This avoids treating an unfinished chord as contrary
        // evidence merely because its identifying note has not arrived yet.
        if challengerQuality >= 0.68 || localQuality >= 0.68 {
            evidence += Double((localOnly & ~observed).nonzeroBitCount) * 0.22
            evidence -= Double((challengerOnly & ~observed).nonzeroBitCount) * 0.22
        }
        if let previous = history.last {
            evidence += transitionAgreement(
                previous: previous,
                current: observation,
                destination: challengerIndex
            ) * 0.35
        }
        return evidence
    }

    // MARK: Evidence and state

    private func expectedLocalIndex(for observation: PerformanceGesture, from origin: Int) -> Int {
        guard let next = score.successor(of: origin, mode: currentMode) else { return origin }
        let currentQuality = matchQuality(observation, at: origin, mode: currentMode)
        let nextQuality = matchQuality(observation, at: next, mode: currentMode)
        return nextQuality >= currentQuality ? next : origin
    }

    private func matchQuality(
        _ observation: PerformanceGesture,
        at index: Int,
        mode: EngravingHandMode
    ) -> Double {
        guard score.gestures.indices.contains(index) else { return 0 }
        return EngravingScoreFeatureIndex.pitchSimilarity(
            observation.pitchMask,
            score.gestures[index].mask(for: mode)
        )
    }

    private func transitionAgreement(
        previous: PerformanceGesture,
        current: PerformanceGesture,
        destination: Int
    ) -> Double {
        guard destination > 0,
              let previousLow = Self.lowestPitch(previous.pitchMask),
              let currentLow = Self.lowestPitch(current.pitchMask),
              let previousHigh = Self.highestPitch(previous.pitchMask),
              let currentHigh = Self.highestPitch(current.pitchMask) else { return 0 }
        let gesture = score.gestures[destination]
        let bassError = abs((currentLow - previousLow) - gesture.bassInterval)
        let sopranoError = abs((currentHigh - previousHigh) - gesture.sopranoInterval)
        return max(-1, 1 - Double(bassError + sopranoError) / 12)
    }

    private func predecessor(of index: Int, mode: EngravingHandMode) -> Int? {
        guard index > 0 else { return nil }
        var candidate = index - 1
        while candidate >= 0 {
            if score.gestures[candidate].mask(for: mode) != 0 { return candidate }
            candidate -= 1
        }
        return nil
    }

    private mutating func updateParticipation(mode: EngravingHandMode, quality: Double) {
        switch mode {
        case .both:
            currentLeftEvidence = quality
            currentRightEvidence = quality
        case .left:
            currentLeftEvidence = quality
            currentRightEvidence = 0
        case .right:
            currentLeftEvidence = 0
            currentRightEvidence = quality
        }
        resolveParticipation()
    }

    private mutating func finalizeParticipationGesture() {
        leftEvidence = leftEvidence * 0.93 + currentLeftEvidence
        rightEvidence = rightEvidence * 0.93 + currentRightEvidence
        currentLeftEvidence = 0
        currentRightEvidence = 0
        resolveParticipation()
    }

    private mutating func resolveParticipation() {
        let totalLeft = leftEvidence + currentLeftEvidence
        let totalRight = rightEvidence + currentRightEvidence
        let stronger = max(totalLeft, totalRight)
        let weaker = min(totalLeft, totalRight)
        if weaker >= 1.45, stronger / max(weaker, 0.001) <= 2.8 {
            participation = .both
        } else if totalLeft >= 2.1, totalLeft > totalRight * 2.8 {
            participation = .left
        } else if totalRight >= 2.1, totalRight > totalLeft * 2.8 {
            participation = .right
        }
    }

    private mutating func recordProvisional(_ index: Int) {
        if provisionalLocalIndices.last != index { provisionalLocalIndices.append(index) }
        if provisionalLocalIndices.count > Configuration.provisionalTailLength {
            provisionalLocalIndices.removeFirst(
                provisionalLocalIndices.count - Configuration.provisionalTailLength
            )
        }
    }

    private func alternativeIndices(including index: Int) -> [Int] {
        var result = [index]
        result.reserveCapacity(5)
        for challenger in challengers where !result.contains(challenger.index) {
            result.append(challenger.index)
            if result.count == 5 { break }
        }
        return result
    }

    private func result(
        index: Int,
        confidence: Double,
        state: EngravingScoreFollower.TrackingState,
        movement: EngravingAlignmentMovement,
        alternatives: [Int]
    ) -> EngravingAlignmentResult {
        EngravingAlignmentResult(
            gestureIndex: index,
            plausibleIndices: alternatives,
            confidence: confidence,
            state: state,
            activeHands: participation,
            movement: movement
        )
    }

    private static func logistic(_ value: Double) -> Double { 1 / (1 + exp(-value)) }

    private static func lowestPitch(_ mask: UInt128) -> Int? {
        mask == 0 ? nil : mask.trailingZeroBitCount
    }

    private static func highestPitch(_ mask: UInt128) -> Int? {
        mask == 0 ? nil : 127 - mask.leadingZeroBitCount
    }
}
