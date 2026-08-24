//
//  ScoreFollower.swift
//  MIDIKit
//
//  Created by Vaida on 2026-08-14.
//

import CoreMIDI
import Foundation
import Optimization


/// Follows a reference score from incoming MIDI note-on messages.
///
/// The follower ranks a bounded set of score-alignment hypotheses. Local advances and
/// distant restarts use the same evidence model, allowing an exact remote phrase to
/// replace an increasingly implausible local continuation.
public final class ScoreFollower {

    /// A note in the score used as alignment reference.
    public struct ReferenceNote: Sendable, Hashable, BitwiseCopyable {
        /// Onset within the reference, measured in beats.
        public let beat: Double

        /// MIDI note number.
        public let pitch: UInt8

        /// Creates a reference note.
        public init(beat: Double, pitch: UInt8) {
            self.beat = beat
            self.pitch = pitch
        }
    }

    /// The follower's current score location.
    public struct Position: Sendable, Hashable, BitwiseCopyable {
        /// The beat of the matched reference moment.
        public let beat: Double

        /// The follower's certainty in the selected alignment, from zero through one.
        public let confidence: Double

        /// Whether this update committed a distant alignment jump.
        public let didJump: Bool

        /// Creates an inferred score position.
        public init(beat: Double, confidence: Double, didJump: Bool) {
            self.beat = beat
            self.confidence = confidence
            self.didJump = didJump
        }
    }

    /// A simultaneous collection of pitches in the score reference.
    public struct ReferenceMoment: Sendable, Hashable {
        /// Onset within the reference, measured in beats.
        public let beat: Double

        /// MIDI note numbers expected at this onset.
        public private(set) var pitches: Set<UInt8>

        /// Creates a reference moment.
        public init(beat: Double, pitches: Set<UInt8>) {
            self.beat = beat
            self.pitches = pitches
        }

        /// Adds a pitch when normalizing adjacent moments with the same onset.
        mutating func insert(_ pitch: UInt8) {
            pitches.insert(pitch)
        }
    }

    private struct Hypothesis {
        var momentIndex: Int
        var matchedPitches: Set<UInt8>
        var releasedPitches: Set<UInt8>
        var score: Double
        var lineageID: Int
        var jumpOriginIndex: Int?
        var jumpTargetStartIndex: Int?
        var jumpConsecutiveConfirmedMoments: Int
        var jumpLastConfirmedMomentIndex: Int?
        var momentStartedAt: MIDITimeStamp?
        var lastMatchedAt: MIDITimeStamp?
        var ticksPerBeat: Double?
        var exactMatchCount: Int
        
        static let initial = [
            Hypothesis(
                momentIndex: -1,
                matchedPitches: [],
                releasedPitches: [],
                score: 0,
                lineageID: 0,
                jumpOriginIndex: nil,
                jumpTargetStartIndex: nil,
                jumpConsecutiveConfirmedMoments: 0,
                jumpLastConfirmedMomentIndex: nil,
                momentStartedAt: nil,
                lastMatchedAt: nil,
                ticksPerBeat: nil,
                exactMatchCount: 0
            )
        ]
    }

    /// Identifies the observable alignment state retained by beam pruning.
    private struct HypothesisState: Hashable {
        let momentIndex: Int
        let matchedPitches: Set<UInt8>
        let releasedPitches: Set<UInt8>
        let lineageID: Int
        let exactMatchCount: Int
    }

    /// Couples a deduplicated hypothesis with its state for beam ranking.
    private struct RankedHypothesis: Comparable {
        let hypothesis: Hypothesis
        let state: HypothesisState

        static func == (lhs: RankedHypothesis, rhs: RankedHypothesis) -> Bool {
            lhs.hypothesis.score == rhs.hypothesis.score
                && lhs.hypothesis.lineageID == rhs.hypothesis.lineageID
        }

        static func < (lhs: RankedHypothesis, rhs: RankedHypothesis) -> Bool {
            lhs.hypothesis.score == rhs.hypothesis.score
                ? lhs.hypothesis.lineageID > rhs.hypothesis.lineageID
                : lhs.hypothesis.score < rhs.hypothesis.score
        }
    }

    private enum Configuration {
        static let simultaneousBeatEpsilon = 1e-6
        static let beamWidth = 24
        static let localLookAhead = 4
        static let regionSize = 8
        static let remoteRestartSeedLimit = 8
        static let exactMatchReward = 4.0
        static let quietNoteMinimumWeight = 0.5
        static let releasedChordPitchReward = 0.2
        static let releasedPitchRearticulationReward = 0.5
        static let unmatchedPitchPenalty = 0.75
        static let completelySkippedMomentPenalty = 1.0
        static let extraPerformedNotePenalty = 2.0
        static let substitutionPenalty = 3.0
        static let jumpPenalty = 8.0
        static let scoreDecay = 0.9
        static let jumpScoreLead = 6.0
        static let jumpWinningStreak = 2
        static let jumpConfirmedChordMoments = 4
        static let jumpMinimumPitchDifferences = 2
        static let initialExactMatchCount = 2
        static let initialScoreLead = 3.0
        static let timingPenaltyWeight = 0.75
        static let timingRatioTolerance = 2.0
        static let practicePauseRatio = 4.0
        static let tempoSmoothing = 0.25
    }

    /// A flattened note representation of the reference, generated only when requested.
    public var reference: [ReferenceNote] {
        moments.flatMap { moment in
            moment.pitches.map { ReferenceNote(beat: moment.beat, pitch: $0) }
        }
    }

    /// The most recently returned position, if a reference moment has been established.
    public private(set) var lastPosition: Position?

    private var moments: [ReferenceMoment] = []
    private var momentsByPitch: [UInt8: [Int]] = [:]
    private var hypotheses: [Hypothesis] = []
    private var committedLineageID = 0
    private var nextLineageID = 1
    private var winningJumpLineageID: Int?
    private var jumpWinningStreak = 0
    private var isAwaitingInitialAlignment = true

    /// Creates an empty score follower.
    ///
    /// Call `update(reference:)` or `update(referenceMoments:)` before consuming MIDI events.
    public init() {
        reset()
    }

    /// Updates the follower with a score reference.
    ///
    /// Notes are sorted and grouped into simultaneous reference moments. Updating replaces the
    /// current reference and resets the follower's alignment state.
    public func update(reference: [ReferenceNote]) async {
        let sorted = reference.sorted {
            $0.beat == $1.beat ? $0.pitch < $1.pitch : $0.beat < $1.beat
        }

        var grouped: [ReferenceMoment] = []
        for note in sorted {
            guard let last = grouped.last,
                  abs(last.beat - note.beat) <= Configuration.simultaneousBeatEpsilon else {
                grouped.append(ReferenceMoment(beat: note.beat, pitches: [note.pitch]))
                continue
            }
            grouped[grouped.count - 1].insert(note.pitch)
        }
        await update(referenceMoments: grouped)
    }

    /// Updates the follower from pre-grouped reference moments.
    ///
    /// Moments are sorted by onset and near-simultaneous moments are merged before indexing.
    /// No intermediary reference notes are created. Updating replaces the current reference and resets
    /// the follower's alignment state.
    public func update(referenceMoments: [ReferenceMoment]) async {
        let sortedMoments = referenceMoments.sorted { $0.beat < $1.beat }
        var groupedMoments: [ReferenceMoment] = []
        for moment in sortedMoments {
            guard let last = groupedMoments.last,
                  abs(last.beat - moment.beat) <= Configuration.simultaneousBeatEpsilon else {
                groupedMoments.append(moment)
                continue
            }
            for pitch in moment.pitches {
                groupedMoments[groupedMoments.count - 1].insert(pitch)
            }
        }
        moments = groupedMoments

        var index: [UInt8: [Int]] = [:]
        for (momentIndex, moment) in groupedMoments.enumerated() {
            for pitch in moment.pitches {
                index[pitch, default: []].append(momentIndex)
            }
        }
        momentsByPitch = index
        reset()
    }

    /// Consumes one timestamped MIDI 1.0 UMP message and returns the inferred score position.
    ///
    /// Note-ons contribute pitch and velocity evidence. Note-offs record chord-release evidence
    /// but do not advance the inferred position. Provide the Core MIDI receive timestamp unchanged;
    /// a zero or non-monotonic timestamp disables timing evidence for the affected transition.
    public func consume(_ input: MIDIInputEvent) -> Position? {
        guard let event = input.parse() else { return nil }

        switch event {
        case let .noteOn(pitch, velocity):
            return consume(noteOn: pitch, velocity: velocity, timestamp: input.timestamp)
        case let .noteOff(pitch):
            consume(noteOff: pitch)
            return nil
        default:
            return nil
        }
    }

    /// Consumes a decoded nonzero-velocity note-on with its receive timestamp.
    ///
    /// This internal entry point keeps alignment independent of Core MIDI packet decoding
    /// and supports deterministic package-level verification.
    func consume(
        noteOn pitch: UInt8,
        velocity: UInt8 = 127,
        timestamp: MIDITimeStamp
    ) -> Position? {
        guard !moments.isEmpty else { return nil }

        let committedAnchor = bestCommittedHypothesis.map(hypothesisState)
        let expanded = hypotheses.flatMap {
            expand(
                $0,
                with: pitch,
                velocity: velocity,
                timestamp: timestamp,
                allowsDistantRestart: committedAnchor == hypothesisState($0)
            )
        }
        hypotheses = prune(expanded)
        return commitPosition()
    }

    /// Records that a performed pitch has been released from every currently matching chord.
    ///
    /// Releases are retained as soft evidence that the performer completed the current chord;
    /// they do not independently cause a score advance.
    func consume(noteOff pitch: UInt8) {
        hypotheses = hypotheses.map { hypothesis in
            guard hypothesis.matchedPitches.contains(pitch) else { return hypothesis }
            var updated = hypothesis
            updated.releasedPitches.insert(pitch)
            return updated
        }
    }

    /// Clears the current alignment and waits for sufficient performance evidence before reporting a position.
    public func reset() {
        hypotheses = Hypothesis.initial // CoW, cheap enough
        committedLineageID = 0
        nextLineageID = 1
        winningJumpLineageID = nil
        jumpWinningStreak = 0
        isAwaitingInitialAlignment = true
        lastPosition = nil
    }

    /// Produces every local and distant interpretation of one performed pitch.
    private func expand(
        _ hypothesis: Hypothesis,
        with pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        allowsDistantRestart: Bool
    ) -> [Hypothesis] {
        var base = hypothesis
        base.score *= Configuration.scoreDecay

        var expansions: [Hypothesis] = []
        if base.momentIndex >= 0,
           moments[base.momentIndex].pitches.contains(pitch),
           !base.matchedPitches.contains(pitch) {
            expansions.append(match(pitch, velocity: velocity, in: base.momentIndex, from: base, timestamp: timestamp))
        }

        var extra = base
        extra.score -= Configuration.extraPerformedNotePenalty
        expansions.append(extra)

        let firstLocalTarget = max(0, base.momentIndex + 1)
        let lastLocalTarget = min(moments.count - 1, base.momentIndex + Configuration.localLookAhead)
        if firstLocalTarget <= lastLocalTarget {
            for target in firstLocalTarget...lastLocalTarget {
                guard moments[target].pitches.contains(pitch) else { continue }
                var advanced = advance(base, to: target, timestamp: timestamp)
                if base.releasedPitches.contains(pitch) {
                    advanced.score += Configuration.releasedPitchRearticulationReward
                }
                expansions.append(match(pitch, velocity: velocity, in: target, from: advanced, timestamp: timestamp))
            }

            let substitutionTarget = max(0, base.momentIndex + 1)
            if substitutionTarget < moments.count {
                var substitution = advance(base, to: substitutionTarget, timestamp: timestamp)
                substitution.score -= Configuration.substitutionPenalty
                expansions.append(substitution)
            }
        }

        if allowsDistantRestart {
            for target in distantRestartTargets(for: pitch, from: base.momentIndex) {
                var restart = restart(from: base, to: target, timestamp: timestamp)
                restart.score -= Configuration.jumpPenalty
                restart.lineageID = nextLineageID
                nextLineageID += 1
                restart.jumpOriginIndex = base.momentIndex
                restart.jumpTargetStartIndex = target
                restart.jumpConsecutiveConfirmedMoments = 0
                restart.jumpLastConfirmedMomentIndex = nil
                expansions.append(match(pitch, velocity: velocity, in: target, from: restart, timestamp: timestamp))
            }
        }

        return expansions
    }

    /// Returns whether transitioning to a score moment should be treated as a distant restart.
    private func isDistant(_ target: Int, from origin: Int) -> Bool {
        guard origin >= 0 else { return target > Configuration.localLookAhead }
        return target < origin || target > origin + Configuration.localLookAhead
    }

    /// Selects a bounded set of remote restart targets distributed across the score.
    private func distantRestartTargets(for pitch: UInt8, from origin: Int) -> [Int] {
        let targets = momentsByPitch[pitch, default: []].filter {
            isDistant($0, from: origin)
        }
        guard targets.count > Configuration.remoteRestartSeedLimit else {
            return targets
        }

        let finalOffset = targets.count - 1
        let offsets = Set((0..<Configuration.remoteRestartSeedLimit).map { seedIndex in
            Int(
                (
                    Double(seedIndex) * Double(finalOffset)
                    / Double(Configuration.remoteRestartSeedLimit - 1)
                ).rounded()
            )
        })
        return offsets.sorted().map { targets[$0] }
    }

    /// Closes the current moment and applies its missing-note and timing costs before advancing.
    private func advance(
        _ hypothesis: Hypothesis,
        to target: Int,
        timestamp: MIDITimeStamp
    ) -> Hypothesis {
        var advanced = hypothesis
        let firstOmitted = max(0, hypothesis.momentIndex)
        if firstOmitted < target {
            for index in firstOmitted..<target {
                let alreadyMatched = index == hypothesis.momentIndex ? hypothesis.matchedPitches : []
                advanced.score -= Configuration.unmatchedPitchPenalty
                    * Double(moments[index].pitches.subtracting(alreadyMatched).count)
                if alreadyMatched.isEmpty {
                    advanced.score -= Configuration.completelySkippedMomentPenalty
                }
            }
        }

        let releasedExpectedPitches = hypothesis.releasedPitches
            .intersection(hypothesis.matchedPitches)
            .count
        advanced.score += Configuration.releasedChordPitchReward * Double(releasedExpectedPitches)

        applyTimingEvidence(to: &advanced, advancingTo: target, timestamp: timestamp)
        advanced.momentIndex = target
        advanced.matchedPitches = []
        advanced.releasedPitches = []
        advanced.momentStartedAt = valid(timestamp) ? timestamp : nil
        advanced.lastMatchedAt = valid(timestamp) ? timestamp : nil
        return advanced
    }

    /// Moves a hypothesis to a distant moment without charging local skipped-moment costs.
    private func restart(
        from hypothesis: Hypothesis,
        to target: Int,
        timestamp: MIDITimeStamp
    ) -> Hypothesis {
        var restarted = hypothesis
        restarted.momentIndex = target
        restarted.matchedPitches = []
        restarted.releasedPitches = []
        restarted.momentStartedAt = valid(timestamp) ? timestamp : nil
        restarted.lastMatchedAt = valid(timestamp) ? timestamp : nil
        restarted.ticksPerBeat = nil
        return restarted
    }

    /// Records a velocity-weighted exact pitch match and updates any pending jump evidence.
    private func match(
        _ pitch: UInt8,
        velocity: UInt8,
        in momentIndex: Int,
        from hypothesis: Hypothesis,
        timestamp: MIDITimeStamp
    ) -> Hypothesis {
        var matched = hypothesis
        matched.momentIndex = momentIndex
        matched.matchedPitches.insert(pitch)
        matched.releasedPitches.remove(pitch)
        matched.score += Configuration.exactMatchReward * velocityWeight(for: velocity)
        matched.exactMatchCount += 1

        if matched.jumpOriginIndex != nil,
           matched.matchedPitches == moments[momentIndex].pitches {
            if isStronglyDistinguishingJumpMoment(momentIndex, in: matched) {
                matched.jumpConsecutiveConfirmedMoments = matched.jumpLastConfirmedMomentIndex == momentIndex - 1
                    ? matched.jumpConsecutiveConfirmedMoments + 1
                    : 1
                matched.jumpLastConfirmedMomentIndex = momentIndex
            } else {
                matched.jumpConsecutiveConfirmedMoments = 0
                matched.jumpLastConfirmedMomentIndex = nil
            }
        }

        if valid(timestamp) {
            if matched.momentStartedAt == nil {
                matched.momentStartedAt = timestamp
            }
            matched.lastMatchedAt = timestamp
        }
        return matched
    }

    /// Returns whether a remote moment differs enough from its uninterrupted local counterpart to confirm a jump.
    private func isStronglyDistinguishingJumpMoment(_ momentIndex: Int, in hypothesis: Hypothesis) -> Bool {
        guard let origin = hypothesis.jumpOriginIndex,
              let targetStart = hypothesis.jumpTargetStartIndex else {
            return false
        }

        let localIndex = origin + (momentIndex - targetStart) + 1
        guard moments.indices.contains(localIndex) else { return true }

        let remotePitches = moments[momentIndex].pitches
        let localPitches = moments[localIndex].pitches
        let minimumDistinctPitches = min(
            Configuration.jumpMinimumPitchDifferences,
            min(remotePitches.count, localPitches.count)
        )
        let differingPitchCount = remotePitches.symmetricDifference(localPitches).count
        return differingPitchCount >= minimumDistinctPitches * 2
    }

    /// Converts MIDI velocity to a bounded confidence weight without excluding quiet notes.
    private func velocityWeight(for velocity: UInt8) -> Double {
        let normalized = Double(velocity) / 127
        return Configuration.quietNoteMinimumWeight
            + (1 - Configuration.quietNoteMinimumWeight) * normalized
    }

    /// Applies soft tempo-relative evidence and updates tempo from complete, reliable moments.
    private func applyTimingEvidence(
        to hypothesis: inout Hypothesis,
        advancingTo target: Int,
        timestamp: MIDITimeStamp
    ) {
        guard hypothesis.momentIndex >= 0,
              let momentStartedAt = hypothesis.momentStartedAt,
              let elapsed = elapsedTicks(from: momentStartedAt, to: timestamp) else {
            return
        }

        let beatDistance = moments[target].beat - moments[hypothesis.momentIndex].beat
        guard beatDistance > 0 else { return }

        let observedTicksPerBeat = elapsed / beatDistance
        guard observedTicksPerBeat > 0 else { return }

        if let ticksPerBeat = hypothesis.ticksPerBeat {
            let ratio = observedTicksPerBeat / ticksPerBeat
            guard ratio <= Configuration.practicePauseRatio else { return }

            let deviation = max(
                0,
                abs(Foundation.log(ratio)) - Foundation.log(Configuration.timingRatioTolerance)
            )
            hypothesis.score -= deviation * Configuration.timingPenaltyWeight

            guard hypothesis.matchedPitches == moments[hypothesis.momentIndex].pitches else { return }
            hypothesis.ticksPerBeat = ticksPerBeat * (1 - Configuration.tempoSmoothing)
                + observedTicksPerBeat * Configuration.tempoSmoothing
        } else if hypothesis.matchedPitches == moments[hypothesis.momentIndex].pitches {
            hypothesis.ticksPerBeat = observedTicksPerBeat
        }
    }

    /// Returns whether a Core MIDI timestamp can be used as timing evidence.
    private func valid(_ timestamp: MIDITimeStamp) -> Bool {
        timestamp != 0
    }

    /// Returns the positive host-clock delta in ticks, ignoring unavailable or reversed input.
    private func elapsedTicks(from earlier: MIDITimeStamp, to later: MIDITimeStamp) -> Double? {
        guard valid(later), later > earlier else { return nil }
        return Double(later - earlier)
    }

    /// Returns the state used to merge equivalent beam candidates.
    private func hypothesisState(_ hypothesis: Hypothesis) -> HypothesisState {
        HypothesisState(
            momentIndex: hypothesis.momentIndex,
            matchedPitches: hypothesis.matchedPitches,
            releasedPitches: hypothesis.releasedPitches,
            lineageID: hypothesis.lineageID,
            exactMatchCount: hypothesis.exactMatchCount
        )
    }

    /// Retains strong, geographically diverse candidate alignments without evicting continuity.
    private func prune(_ candidates: [Hypothesis]) -> [Hypothesis] {
        var bestByState = Dictionary<HypothesisState, Hypothesis>(minimumCapacity: candidates.count)
        for candidate in candidates {
            let state = hypothesisState(candidate)
            if bestByState[state]?.score ?? -.infinity < candidate.score {
                bestByState[state] = candidate
            }
        }

        let ranked = bestByState.values.map {
            RankedHypothesis(
                hypothesis: $0,
                state: hypothesisState($0)
            )
        }
        let committed = ranked
            .filter { $0.hypothesis.lineageID == committedLineageID }
            .max()

        var selected: [RankedHypothesis] = []
        selected.reserveCapacity(Configuration.beamWidth)
        if let committed {
            selected.append(committed)
        } else {
            assertionFailure("Beam pruning must retain the committed lineage.")
        }

        let remainingCapacity = Configuration.beamWidth - selected.count
        let committedRegion = committed.map {
            $0.hypothesis.momentIndex < 0
                ? -1
                : $0.hypothesis.momentIndex / Configuration.regionSize
        }
        var bestByRegion: [Int: RankedHypothesis] = [:]
        for candidate in ranked where candidate.state != committed?.state {
            let region = candidate.hypothesis.momentIndex < 0
                ? -1
                : candidate.hypothesis.momentIndex / Configuration.regionSize
            guard region != committedRegion else { continue }
            if let existing = bestByRegion[region], existing >= candidate {
                continue
            }
            bestByRegion[region] = candidate
        }

        var regionCandidates = Heap<RankedHypothesis>(.minHeap)
        for candidate in bestByRegion.values {
            regionCandidates.append(candidate)
            if regionCandidates.count > remainingCapacity {
                regionCandidates.removeFirst()
            }
        }
        selected.append(contentsOf: regionCandidates.sorted(by: >))

        let selectedStates = Set(selected.map { $0.state })
        let fillCapacity = Configuration.beamWidth - selected.count
        var fillCandidates = Heap<RankedHypothesis>(.minHeap)
        for candidate in ranked where !selectedStates.contains(candidate.state) {
            fillCandidates.append(candidate)
            if fillCandidates.count > fillCapacity {
                fillCandidates.removeFirst()
            }
        }
        selected.append(contentsOf: fillCandidates.sorted(by: >))

        return selected.map { $0.hypothesis }
    }

    /// Selects the committed lineage and applies confirmation before accepting a distant jump.
    private func commitPosition() -> Position? {
        if isAwaitingInitialAlignment {
            guard let initial = bestInitialHypothesis,
                  canCommit(initialAlignment: initial) else {
                return nil
            }

            committedLineageID = initial.lineageID
            isAwaitingInitialAlignment = false
            hypotheses = hypotheses.map { hypothesis in
                guard hypothesis.lineageID == initial.lineageID else { return hypothesis }
                var promoted = hypothesis
                promoted.jumpOriginIndex = nil
                promoted.jumpTargetStartIndex = nil
                promoted.jumpConsecutiveConfirmedMoments = 0
                promoted.jumpLastConfirmedMomentIndex = nil
                return promoted
            }
            return makePosition(from: initial, didJump: initial.jumpOriginIndex != nil)
        }

        guard let committed = bestCommittedHypothesis else { return nil }

        if let jump = bestJumpHypothesis,
           canCommit(jump: jump, over: committed) {
            if winningJumpLineageID == jump.lineageID {
                jumpWinningStreak += 1
            } else {
                winningJumpLineageID = jump.lineageID
                jumpWinningStreak = 1
            }

            if jumpWinningStreak >= Configuration.jumpWinningStreak {
                committedLineageID = jump.lineageID
                hypotheses = hypotheses.map {
                    guard $0.lineageID == jump.lineageID else { return $0 }
                    var promoted = $0
                    promoted.jumpOriginIndex = nil
                    promoted.jumpTargetStartIndex = nil
                    promoted.jumpConsecutiveConfirmedMoments = 0
                    promoted.jumpLastConfirmedMomentIndex = nil
                    return promoted
                }
                winningJumpLineageID = nil
                jumpWinningStreak = 0
                return makePosition(from: jump, didJump: true)
            }
        } else {
            winningJumpLineageID = nil
            jumpWinningStreak = 0
        }

        return makePosition(from: committed, didJump: false)
    }

    /// Returns the strongest complete alignment candidate while no score location has been committed.
    private var bestInitialHypothesis: Hypothesis? {
        hypotheses
            .filter {
                $0.momentIndex >= 0
                    && $0.matchedPitches == moments[$0.momentIndex].pitches
            }
            .max(by: { $0.score < $1.score })
    }

    /// Returns whether an initial candidate is supported by sufficient distinct performed-note evidence.
    private func canCommit(initialAlignment hypothesis: Hypothesis) -> Bool {
        guard hypothesis.exactMatchCount >= Configuration.initialExactMatchCount else {
            return false
        }

        let state = hypothesisState(hypothesis)
        guard let alternative = hypotheses
            .filter({ hypothesisState($0) != state })
            .max(by: { $0.score < $1.score }) else {
            return false
        }
        return hypothesis.score >= alternative.score + Configuration.initialScoreLead
    }

    /// Returns the strongest hypothesis in the currently committed lineage.
    private var bestCommittedHypothesis: Hypothesis? {
        hypotheses
            .filter { $0.lineageID == committedLineageID }
            .max(by: { $0.score < $1.score })
    }

    /// Returns the strongest uncommitted hypothesis created by a distant restart.
    private var bestJumpHypothesis: Hypothesis? {
        hypotheses
            .filter { $0.lineageID != committedLineageID && $0.jumpOriginIndex != nil }
            .max(by: { $0.score < $1.score })
    }

    /// Returns whether a distant hypothesis has enough sustained evidence to replace continuity.
    private func canCommit(jump: Hypothesis, over committed: Hypothesis) -> Bool {
        guard jump.momentIndex != committed.momentIndex,
              jump.jumpConsecutiveConfirmedMoments >= Configuration.jumpConfirmedChordMoments else {
            return false
        }
        return jump.score >= committed.score + Configuration.jumpScoreLead
    }

    /// Creates a public position and derives confidence from the strongest competing lineage.
    private func makePosition(from hypothesis: Hypothesis, didJump: Bool) -> Position? {
        guard hypothesis.momentIndex >= 0 else { return nil }

        let alternative = hypotheses
            .filter { $0.lineageID != hypothesis.lineageID }
            .max(by: { $0.score < $1.score })
        let confidence: Double
        if let alternative {
            let gap = hypothesis.score - alternative.score
            confidence = 1 / (1 + Foundation.exp(-gap / 3))
        } else {
            confidence = 0.9
        }

        let position = Position(
            beat: moments[hypothesis.momentIndex].beat,
            confidence: min(1, max(0, confidence)),
            didJump: didJump
        )
        lastPosition = position
        return position
    }
}
