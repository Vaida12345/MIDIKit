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
        let lookupIsExhaustive: Bool
        let sequenceIsExact: Bool
        let observationCount: Int

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
        var localBaseIndex: Int
        var localIndex: Int
        var completedEvidence: Double
        var currentEvidence: Double
        var currentDistinguishingEvidence: Double
        var qualityTotal: Double
        var currentQuality: Double
        var completedCoherentRun: Int
        var completedDistinguishingCount: Int
        var currentObservedMask: UInt128
        var lastCompletedObservedMask: UInt128?
        var destinationIsCertifiedUnique: Bool
        var clock: PerformanceTempoTracker

        var evidence: Double { completedEvidence + currentEvidence }
        var averageQuality: Double {
            qualityTotal / Double(max(1, completedCoherentRun))
        }
    }

    private struct RelativeEvidence {
        let total: Double
        /// Candidate-relative musical evidence only. Timing is deliberately excluded so it
        /// cannot turn an otherwise ambiguous observation into a relocation anchor.
        let distinguishing: Double
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
    private var acquisitionGestureContext: PerformanceGestureContext?
    private var relocationRearmProgress = 2

    /// Acquisition evidence is intentionally private until a score location is committed.
    /// The façade uses this bit only to distinguish a useful but still ambiguous first gesture
    /// from an out-of-reference note that should not latch the performance epoch.
    private(set) var hasAcquisitionEvidence = false

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
        hasAcquisitionEvidence = false
        acquisitionGestureContext = nil
        relocationRearmProgress = 2
    }

    mutating func setVisibleRange(_ range: ClosedRange<Double>?) {
        visibleRange = range
    }

    var gestureContext: PerformanceGestureContext {
        guard let currentIndex else { return acquisitionGestureContext ?? .unknown }
        let expectedIndex = assemblyExpectationIndex ?? currentIndex
        var currentMasks = score.gestures[expectedIndex].masks
        var attack = score.gestures[expectedIndex].attack

        // Only an episode that already completed one coherent, independently localized gesture
        // may inform segmentation of its *next* gesture. The seed gesture cannot shape itself,
        // which removes the former candidate/evidence feedback loop while retaining slow and
        // serialized remote-chord support.
        for challenger in challengers.prefix(8)
        where challenger.completedCoherentRun >= 1
            && challenger.destinationIsCertifiedUnique
            && score.gestures.indices.contains(challenger.index) {
            let gesture = score.gestures[challenger.index]
            currentMasks[challenger.mode] |= gesture.mask(for: challenger.mode)
            currentMasks[.both] |= gesture.mask(for: challenger.mode)
            if gesture.attack == .rolled { attack = .rolled }
        }

        var nextMasks = EngravingPitchMasks()
        for mode in EngravingHandMode.allCases {
            if let next = score.successor(of: expectedIndex, mode: mode) {
                nextMasks[mode] = score.gestures[next].mask(for: mode)
            }
        }
        for challenger in challengers.prefix(8)
        where challenger.completedCoherentRun >= 1
            && challenger.destinationIsCertifiedUnique {
            guard let next = score.successor(of: challenger.index, mode: challenger.mode) else {
                continue
            }
            let mask = score.gestures[next].mask(for: challenger.mode)
            nextMasks[challenger.mode] |= mask
            nextMasks[.both] |= mask
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
        hasAcquisitionEvidence = !candidates.isEmpty
        acquisitionGestureContext = makeAcquisitionGestureContext(from: candidates)
        guard !candidates.isEmpty else { return nil }

        // Acquisition hypotheses are not committed musical positions. In particular they must
        // not move the forward frontier or initialize presentation while repeated material is
        // unresolved. `Update` is optional specifically so the façade can remain silent here.
        var bestByDestination: [Int: AcquisitionCandidate] = [:]
        for candidate in candidates {
            if bestByDestination[candidate.index]?.score ?? -.infinity < candidate.score {
                bestByDestination[candidate.index] = candidate
            }
        }
        let destinations = bestByDestination.values.sorted {
            $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score
        }
        guard let destination = destinations.first else { return nil }
        let exactCandidates = candidates.filter(\.sequenceIsExact)
        let exactDestinations = Set(exactCandidates.map(\.index))
        let destinationIsGloballyUnique = exactDestinations == Set([destination.index])
            && exactCandidates.allSatisfy(\.lookupIsExhaustive)

        let scoreGesture = score.gestures[destination.index]
        let quality = matchQuality(
            observation,
            at: destination.index,
            mode: destination.mode
        )
        let currentIsResolved = observation.pitchMask == scoreGesture.mask(for: destination.mode)
        let informativeCompleteChord = observation.pitchMask.nonzeroBitCount > 1
            && currentIsResolved
            && quality >= 0.96
            && (destination.mode == .both
                || scoreGesture.mask(for: destination.mode) == scoreGesture.mask(for: .both))
        let destinationIsVisible = score.isVisible(destination.index, in: acquisitionRange)
        let scoreLead = destinations.count > 1
            ? destination.score - destinations[1].score
            : .infinity
        let visiblePriorResolvesAlias = destinationIsVisible
            && destination.sequenceIsExact
            && destination.observationCount >= 2
            && scoreLead >= 1.8
        let corroboratedOffscreenContext = !destinationIsVisible
            && destinationIsGloballyUnique
            && destination.sequenceIsExact
            && destination.observationCount >= 3
            && scoreLead >= 4.5
        let uniqueCompleteChord = destinationIsGloballyUnique && informativeCompleteChord
        guard uniqueCompleteChord || visiblePriorResolvesAlias || corroboratedOffscreenContext else {
            return nil
        }

        currentIndex = destination.index
        currentMode = destination.mode
        assemblyExpectationIndex = destination.index
        forwardFrontier = destination.index
        updateParticipation(mode: destination.mode, quality: quality)
        isTracking = true
        acquisitionGestureContext = nil
        transitionOriginIndex = destination.index
        provisionalLocalIndices = [destination.index]
        hasAlignedCurrentGesture = true
        timing.anchorLocal(at: observation.startedAt, beat: score.gestures[destination.index].beat)

        let margin = destinations.count > 1 ? destination.score - destinations[1].score : 4
        let confidence = Self.logistic(margin / 1.6)
        let acquiredOffscreen = acquisitionRange != nil
            && !score.isVisible(destination.index, in: acquisitionRange)
        let movement: EngravingAlignmentMovement = acquiredOffscreen ? .jump : .held
        return result(
            index: destination.index,
            confidence: confidence,
            state: .tracking,
            movement: movement,
            alternatives: destinations.prefix(5).map(\.index)
        )
    }

    private func acquisitionCandidates(
        observation: PerformanceGesture,
        previous: PerformanceGesture?
    ) -> [AcquisitionCandidate] {
        var best: [AcquisitionCandidate: AcquisitionCandidate] = [:]
        best.reserveCapacity(Configuration.acquisitionCandidatesPerMode * 3)
        let observations = Array(history.suffix(Configuration.maximumHistory - 1)) + [observation]

        for mode in EngravingHandMode.allCases {
            let currentLookup = score.candidateLookup(
                for: observation.pitchMask,
                previousMask: previous?.pitchMask,
                mode: mode,
                limit: Configuration.acquisitionCandidatesPerMode
            )
            var candidateIndices = currentLookup.indices
            var lookupIsExhaustive = currentLookup.isExhaustive

            // A wrong note may have no posting at the correct location. Preserve the continuity
            // alternative by advancing candidates found from the preceding observation.
            if let previous {
                let previousLookup = score.candidateLookup(
                    for: previous.pitchMask,
                    previousMask: history.dropLast().last?.pitchMask,
                    mode: mode,
                    limit: Configuration.acquisitionCandidatesPerMode
                )
                lookupIsExhaustive = lookupIsExhaustive && previousLookup.isExhaustive
                for previousIndex in previousLookup.indices {
                    if let next = score.successor(of: previousIndex, mode: mode),
                       !candidateIndices.contains(next) {
                        candidateIndices.append(next)
                    }
                }
            }

            for index in candidateIndices {
                var value = 0.0
                var compared = 0
                var sequenceIsExact = true
                var scoreIndex: Int? = index
                for performed in observations.reversed() {
                    guard let comparedIndex = scoreIndex else {
                        sequenceIsExact = false
                        break
                    }
                    let quality = matchQuality(performed, at: comparedIndex, mode: mode)
                    let weight = compared == 0 ? 6.0 : 5.0
                    value += quality * weight
                    sequenceIsExact = sequenceIsExact
                        && performed.pitchMask == score.gestures[comparedIndex].mask(for: mode)
                    compared += 1
                    scoreIndex = predecessor(of: comparedIndex, mode: mode)
                }
                if let previous {
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
                let candidate = AcquisitionCandidate(
                    index: index,
                    mode: mode,
                    score: value,
                    lookupIsExhaustive: lookupIsExhaustive,
                    sequenceIsExact: sequenceIsExact,
                    observationCount: compared
                )
                if best[candidate]?.score ?? -.infinity < value { best[candidate] = candidate }
            }
        }
        return best.values.sorted {
            $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score
        }
    }

    /// Supplies bounded chord-membership alternatives while acquisition is unresolved. These
    /// masks affect only physical gesture segmentation; they never become a committed score
    /// location or relocation vote.
    private func makeAcquisitionGestureContext(
        from candidates: [AcquisitionCandidate]
    ) -> PerformanceGestureContext? {
        guard !candidates.isEmpty else { return nil }
        var currentMasks = EngravingPitchMasks()
        var nextMasks = EngravingPitchMasks()
        var attack: EngravingReference.Attack = .block
        for candidate in candidates.prefix(8) {
            let gesture = score.gestures[candidate.index]
            currentMasks[candidate.mode] |= gesture.mask(for: candidate.mode)
            currentMasks[.both] |= gesture.mask(for: candidate.mode)
            if gesture.attack == .rolled { attack = .rolled }
            if let next = score.successor(of: candidate.index, mode: candidate.mode) {
                nextMasks[candidate.mode] |= score.gestures[next].mask(for: candidate.mode)
                nextMasks[.both] |= score.gestures[next].mask(for: candidate.mode)
            }
        }
        return PerformanceGestureContext(
            currentMasks: currentMasks,
            nextMasks: nextMasks,
            attack: attack,
            timing: timing.gestureHint(for: attack)
        )
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
            // Crossing multiple engraving lines is an intervention, not a local transition.
            // Presentation is forbidden from manufacturing relocation authority after the fact,
            // so such a destination must be established by the guarded global mechanism.
            guard score.gestures[next].lineOffset
                    <= score.gestures[origin].lineOffset + 1 else { continue }
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

            if let second = score.successor(of: next, mode: mode),
               score.gestures[second].lineOffset
                    <= score.gestures[origin].lineOffset + 1 {
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
        if quality >= 0.75 {
            relocationRearmProgress = min(2, relocationRearmProgress + 1)
        }
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
        guard relocationRearmProgress >= 2 else {
            challengers.removeAll(keepingCapacity: true)
            return
        }
        let localExpected = expectedLocalIndex(for: observation, from: localOrigin)
        var updated: [Challenger] = []
        updated.reserveCapacity(Configuration.challengerBeamWidth * 2)

        for var challenger in challengers {
            var transitionTimingEvidence = 0.0
            // A seed's current gesture is the possible change point. It has no legitimate
            // predecessor at the destination, even when later MIDI notes extend that gesture.
            var includesTransitionEvidence = challenger.completedCoherentRun > 0
            if beginsNewGesture {
                guard let next = score.successor(of: challenger.index, mode: challenger.mode) else {
                    continue
                }
                let coherent = challenger.currentQuality >= 0.50
                // Contradiction terminates this possible change point. A later observation may
                // seed a new episode, but evidence from the two episodes is never combined.
                guard coherent else { continue }
                challenger.completedEvidence += challenger.currentEvidence
                challenger.qualityTotal += challenger.currentQuality
                challenger.completedCoherentRun += 1
                includesTransitionEvidence = true
                if challenger.currentDistinguishingEvidence >= 0.75 {
                    challenger.completedDistinguishingCount += 1
                }
                challenger.lastCompletedObservedMask = challenger.currentObservedMask
                challenger.currentEvidence = 0
                challenger.currentDistinguishingEvidence = 0
                challenger.currentQuality = 0
                challenger.index = next
                challenger.localBaseIndex = challenger.localIndex
                challenger.localIndex = counterfactualLocalIndex(
                    for: observation,
                    from: challenger.localBaseIndex,
                    mode: currentMode
                )
                transitionTimingEvidence = challenger.clock.compatibility(
                    at: observation.startedAt,
                    beat: score.gestures[next].beat
                )
            } else {
                challenger.localIndex = counterfactualLocalIndex(
                    for: observation,
                    from: challenger.localBaseIndex,
                    mode: currentMode
                )
            }
            let relative = relativeEvidence(
                observation,
                challengerIndex: challenger.index,
                challengerMode: challenger.mode,
                localIndex: challenger.localIndex,
                localMode: currentMode,
                includesTransition: includesTransitionEvidence
            )
            challenger.currentEvidence = relative.total + transitionTimingEvidence * 0.45
            challenger.currentDistinguishingEvidence = relative.distinguishing
            challenger.currentQuality = matchQuality(
                observation,
                at: challenger.index,
                mode: challenger.mode
            )
            challenger.currentObservedMask = observation.pitchMask
            if observation.pitchMask == score.gestures[challenger.index].mask(for: challenger.mode),
               relocationCertificate(
                    for: observation.pitchMask,
                    previousMask: challenger.lastCompletedObservedMask
               ) == challenger.index {
                challenger.destinationIsCertifiedUnique = true
            }
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
            let lookup = score.candidateLookup(
                for: observation.pitchMask,
                previousMask: nil,
                mode: mode,
                limit: Configuration.challengerSeedsPerMode
            )
            let certifiedDestination = relocationCertificate(
                for: observation.pitchMask,
                previousMask: nil
            )
            for index in lookup.indices {
                if abs(index - localOrigin) <= 2 { continue }
                let quality = matchQuality(observation, at: index, mode: mode)
                guard quality >= 0.42 else { continue }
                var clock = PerformanceTempoTracker()
                clock.reset(at: observation.startedAt, beat: score.gestures[index].beat)
                let relative = relativeEvidence(
                    observation,
                    challengerIndex: index,
                    challengerMode: mode,
                    localIndex: localExpected,
                    localMode: currentMode,
                    includesTransition: false
                )
                updated.append(Challenger(
                    index: index,
                    mode: mode,
                    seedIndex: index,
                    localBaseIndex: localOrigin,
                    localIndex: localExpected,
                    completedEvidence: -Configuration.restartPenalty,
                    currentEvidence: relative.total,
                    currentDistinguishingEvidence: relative.distinguishing,
                    qualityTotal: 0,
                    currentQuality: quality,
                    completedCoherentRun: 0,
                    completedDistinguishingCount: 0,
                    currentObservedMask: observation.pitchMask,
                    lastCompletedObservedMask: nil,
                    destinationIsCertifiedUnique: certifiedDestination == index,
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
        guard let incumbent = currentIndex else { return nil }

        // Modes and seed histories that currently name the same score destination are one
        // presentation hypothesis. Distinct score destinations remain competitors: if more
        // than one is ready, the music is observationally ambiguous and continuity wins.
        var bestByDestination: [Int: Challenger] = [:]
        for challenger in challengers {
            if bestByDestination[challenger.index]?.evidence ?? -.infinity
                < challenger.evidence {
                bestByDestination[challenger.index] = challenger
            }
        }

        let ready = bestByDestination.values.filter { challenger in
            let destinationVisible = score.isVisible(challenger.index, in: visibleRange)
            let isEarlier = challenger.index < (forwardFrontier ?? incumbent)
            let requiredEvidence = isEarlier && destinationVisible
                ? Configuration.replayEvidence
                : Configuration.jumpEvidence

            let expected = score.gestures[challenger.index].mask(for: challenger.mode)
            let currentIsResolved = observation.pitchMask == expected
            let currentIsCoherent = currentIsResolved
                && challenger.currentQuality >= 0.50
                && challenger.currentDistinguishingEvidence > -0.75
            let coherentRun = challenger.completedCoherentRun + (currentIsCoherent ? 1 : 0)
            let distinguishingCount = challenger.completedDistinguishingCount
                + (currentIsCoherent && challenger.currentDistinguishingEvidence >= 0.75 ? 1 : 0)
            let evidence = challenger.completedEvidence
                + (currentIsCoherent ? challenger.currentEvidence : 0)
            let qualityTotal = challenger.qualityTotal
                + (currentIsCoherent ? challenger.currentQuality : 0)
            let averageQuality = qualityTotal / Double(max(1, coherentRun))
            // The three observations have different jobs: establish a possible change point,
            // continue coherently from it, and confirm the new episode. At least two must
            // actually distinguish this destination from local continuity. Only completed
            // gestures, or an exactly resolved current gesture, participate in the decision.
            return coherentRun >= 3
                && distinguishingCount >= 2
                && evidence >= requiredEvidence
                && averageQuality >= 0.62
                && challenger.destinationIsCertifiedUnique
        }
        guard ready.count == 1, let best = ready.first else { return nil }

        let destinationVisible = score.isVisible(best.index, in: visibleRange)
        let isEarlier = best.index < (forwardFrontier ?? incumbent)

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
            relocationRearmProgress = 0
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
        localMode: EngravingHandMode,
        includesTransition: Bool
    ) -> RelativeEvidence {
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
        if includesTransition, let previous = history.last {
            let challengerTransition = transitionAgreement(
                previous: previous,
                current: observation,
                destination: challengerIndex
            )
            let localTransition = transitionAgreement(
                previous: previous,
                current: observation,
                destination: localIndex
            )
            evidence += (challengerTransition - localTransition) * 0.35
        }
        // A dense chord is one physical observation, not a dozen independent votes. Capping its
        // contribution prevents two spectacular chords plus neutral material from overwhelming
        // the episode-level confirmation rule.
        let bounded = min(5, max(-5, evidence))
        return RelativeEvidence(total: bounded, distinguishing: bounded)
    }

    // MARK: Evidence and state

    /// Advances the no-jump explanation as its own monotone path. It may absorb an insertion or
    /// one omitted score gesture, but it cannot choose a fresh unrelated local position after
    /// seeing each observation.
    private func counterfactualLocalIndex(
        for observation: PerformanceGesture,
        from origin: Int,
        mode: EngravingHandMode
    ) -> Int {
        var bestIndex = origin
        var bestScore = matchQuality(observation, at: origin, mode: mode) * 5
            - Configuration.insertionPenalty
        if let next = score.successor(of: origin, mode: mode) {
            let nextScore = matchQuality(observation, at: next, mode: mode) * 5 + 0.55
            if nextScore > bestScore {
                bestIndex = next
                bestScore = nextScore
            }
            if let second = score.successor(of: next, mode: mode) {
                let skipScore = matchQuality(observation, at: second, mode: mode) * 5
                    - Configuration.deletionPenalty
                if skipScore > bestScore { bestIndex = second }
            }
        }
        return bestIndex
    }

    /// Proves uniqueness independently of the challenger beam. `nil` means either that several
    /// score destinations remain compatible or that bounded lookup could not exhaust them.
    private func relocationCertificate(
        for observedMask: UInt128,
        previousMask: UInt128?
    ) -> Int? {
        var destinations = Set<Int>()
        for mode in EngravingHandMode.allCases {
            let lookup = score.candidateLookup(
                for: observedMask,
                previousMask: previousMask,
                mode: mode,
                limit: Configuration.challengerSeedsPerMode
            )
            guard lookup.isExhaustive else { return nil }
            for index in lookup.indices {
                let quality = EngravingScoreFeatureIndex.pitchSimilarity(
                    observedMask,
                    score.gestures[index].mask(for: mode)
                )
                if quality >= 0.62 { destinations.insert(index) }
                if destinations.count > 1 { return nil }
            }
        }
        return destinations.count == 1 ? destinations.first : nil
    }

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
