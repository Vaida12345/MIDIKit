//
//  ScoreFollower.swift
//  MIDIKit
//
//  Created by Vaida on 2026-08-14.
//

import CoreMIDI
import Foundation


/// Follows a reference score from incoming MIDI note-on messages.
///
/// The follower deliberately uses note identity only: tempo, timestamps, durations, and
/// velocity magnitude do not influence alignment. This makes it suitable for live input
/// where timing may be expressive or unavailable.
public final class ScoreFollower {

    /// A note in the score used as alignment reference.
    public struct ReferenceNote: Sendable {
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
    public struct Position: Sendable {
        /// The beat of the matched reference moment.
        public let beat: Double

        /// The follower's certainty in the selected alignment, from zero through one.
        public let confidence: Double

        /// Whether this update committed a global recovery jump.
        public let didJump: Bool

        /// Creates an inferred score position.
        public init(beat: Double, confidence: Double, didJump: Bool) {
            self.beat = beat
            self.confidence = confidence
            self.didJump = didJump
        }
    }

    /// A simultaneous collection of pitches in the score reference.
    public struct ReferenceMoment: Sendable {
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
        var recentExactMatches: Int
        var recentlyMatchedMoments: Set<Int>
        var lineageID: Int
        var isRecovery: Bool
        var momentStartedAt: MIDITimeStamp?
        var lastMatchedAt: MIDITimeStamp?
        var ticksPerBeat: Double?
    }

    /// A reference location and its bounded evidence from recent performed pitches.
    private struct RecoveryCandidate {
        let momentIndex: Int
        let exactMatches: Int
        let matchedMoments: Set<Int>
    }

    private enum Configuration {
        static let simultaneousBeatEpsilon = 1e-6
        static let beamWidth = 24
        static let localLookAhead = 4
        static let observationLimit = 12
        static let recoveryInterval = 4
        static let recoveryHypothesisLimit = 4
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
        static let recoveryScoreLead = 6.0
        static let recoveryWinningStreak = 2
        static let recoveryExactMatches = 4
        static let recoveryDistinctMoments = 3
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

    private let moments: [ReferenceMoment]
    private let momentsByPitch: [UInt8: [Int]]
    private var hypotheses: [Hypothesis] = []
    private var observations: [UInt8] = []
    private var acceptedNoteCount = 0
    private var committedLineageID = 0
    private var nextLineageID = 1
    private var recoveryWinningLineageID: Int?
    private var recoveryWinningStreak = 0

    /// Creates a follower for the supplied score reference.
    ///
    /// Notes are sorted and grouped into simultaneous reference moments.
    public convenience init(reference: [ReferenceNote]) {
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
        self.init(referenceMoments: grouped)
    }

    /// Creates a follower from pre-grouped reference moments.
    ///
    /// Moments are sorted by onset before indexing. No intermediary reference notes are created.
    public init(referenceMoments: [ReferenceMoment]) {
        let sortedMoments = referenceMoments.sorted { $0.beat < $1.beat }
        moments = sortedMoments

        var index: [UInt8: [Int]] = [:]
        for (momentIndex, moment) in sortedMoments.enumerated() {
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
    public func consume(
        _ message: MIDIUniversalMessage,
        timestamp: MIDITimeStamp
    ) -> Position? {
        guard let event = noteEvent(from: message) else { return nil }

        switch event {
        case let .noteOn(pitch, velocity):
            return consume(noteOn: pitch, velocity: velocity, timestamp: timestamp)
        case let .noteOff(pitch):
            consume(noteOff: pitch)
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

        acceptedNoteCount += 1
        observations.append(pitch)
        if observations.count > Configuration.observationLimit {
            observations.removeFirst()
        }

        let expanded = hypotheses.flatMap {
            expand($0, with: pitch, velocity: velocity, timestamp: timestamp)
        }
        hypotheses = prune(expanded)

        if shouldAttemptRecovery {
            hypotheses = prune(hypotheses + recoveryHypotheses(for: pitch, velocity: velocity, timestamp: timestamp))
        }

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

    /// Restores the follower to the state before the first reference moment.
    public func reset() {
        hypotheses = [Hypothesis(
            momentIndex: -1,
            matchedPitches: [],
            releasedPitches: [],
            score: 0,
            recentExactMatches: 0,
            recentlyMatchedMoments: [],
            lineageID: 0,
            isRecovery: false,
            momentStartedAt: nil,
            lastMatchedAt: nil,
            ticksPerBeat: nil
        )]
        observations.removeAll(keepingCapacity: true)
        acceptedNoteCount = 0
        committedLineageID = 0
        nextLineageID = 1
        recoveryWinningLineageID = nil
        recoveryWinningStreak = 0
        lastPosition = nil
    }

    /// A MIDI 1.0 note event decoded from a Universal MIDI Packet.
    private enum NoteEvent {
        case noteOn(pitch: UInt8, velocity: UInt8)
        case noteOff(pitch: UInt8)
    }

    /// Extracts MIDI 1.0 UMP note events while keeping packet decoding out of the aligner.
    private func noteEvent(from message: MIDIUniversalMessage) -> NoteEvent? {
        // `MIDIUniversalMessage` is an inline UMP word container. The UMP words are
        // native-endian, so reading the first word directly preserves the Core MIDI layout.
        let word = withUnsafeBytes(of: message) { $0.loadUnaligned(as: UInt32.self) }
        let messageType = UInt8((word >> 28) & 0x0F)
        guard messageType == 0x2 else { return nil }

        let status = UInt8((word >> 16) & 0xFF)
        let pitch = UInt8((word >> 8) & 0x7F)
        let velocity = UInt8(word & 0x7F)

        switch status & 0xF0 {
        case 0x80:
            return .noteOff(pitch: pitch)
        case 0x90:
            return velocity > 0
                ? .noteOn(pitch: pitch, velocity: velocity)
                : .noteOff(pitch: pitch)
        default:
            return nil
        }
    }

    private var shouldAttemptRecovery: Bool {
        guard !observations.isEmpty else { return false }
        guard acceptedNoteCount.isMultiple(of: Configuration.recoveryInterval) else {
            return bestCommittedHypothesis?.score ?? 0 < -4
        }
        return true
    }

    /// Creates bounded local interpretations of one timestamped performed pitch.
    ///
    /// An incomplete reference moment remains open while later notes can complete it. Timing
    /// only changes the score of alternatives that advance to another reference moment.
    private func expand(
        _ hypothesis: Hypothesis,
        with pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp
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

        let firstTarget = max(0, base.momentIndex + 1)
        let lastTarget = min(moments.count - 1, base.momentIndex + Configuration.localLookAhead)
        guard firstTarget <= lastTarget else { return expansions }

        for target in firstTarget...lastTarget {
            guard moments[target].pitches.contains(pitch) else { continue }
            var advanced = advance(base, to: target, timestamp: timestamp)
            if base.releasedPitches.contains(pitch) {
                advanced.score += Configuration.releasedPitchRearticulationReward
            }
            advanced = match(pitch, velocity: velocity, in: target, from: advanced, timestamp: timestamp)
            expansions.append(advanced)
        }

        // A substitution advances one moment even when the pitch is wrong, avoiding a
        // permanent stall after a single wrong note.
        let substitutionTarget = max(0, base.momentIndex + 1)
        if substitutionTarget < moments.count {
            var substitution = advance(base, to: substitutionTarget, timestamp: timestamp)
            substitution.score -= Configuration.substitutionPenalty
            expansions.append(substitution)
        }
        return expansions
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
                advanced.score -= Configuration.unmatchedPitchPenalty * Double(moments[index].pitches.subtracting(alreadyMatched).count)
                advanced.score -= Configuration.completelySkippedMomentPenalty
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

    /// Records a velocity-weighted exact pitch match and retains bounded jump evidence.
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
        matched.recentExactMatches = min(Configuration.observationLimit, matched.recentExactMatches + 1)
        matched.recentlyMatchedMoments.insert(momentIndex)
        if matched.recentlyMatchedMoments.count > 6,
           let oldest = matched.recentlyMatchedMoments.min() {
            matched.recentlyMatchedMoments.remove(oldest)
        }
        if valid(timestamp) {
            if matched.momentStartedAt == nil {
                matched.momentStartedAt = timestamp
            }
            matched.lastMatchedAt = timestamp
        }
        return matched
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

            let deviation = max(0, abs(Foundation.log(ratio)) - Foundation.log(Configuration.timingRatioTolerance))
            hypothesis.score -= deviation * Configuration.timingPenaltyWeight

            guard hypothesis.matchedPitches == moments[hypothesis.momentIndex].pitches else {
                return
            }
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

    /// Keeps only the strongest representative of each alignment state.
    private func prune(_ candidates: [Hypothesis]) -> [Hypothesis] {
        var bestByState: [String: Hypothesis] = [:]
        for candidate in candidates {
            let matchedPitches = candidate.matchedPitches.sorted().map(String.init).joined(separator: ",")
            let releasedPitches = candidate.releasedPitches.sorted().map(String.init).joined(separator: ",")
            let key = "\(candidate.momentIndex)|\(matchedPitches)|\(releasedPitches)|\(candidate.lineageID)"
            if bestByState[key]?.score ?? -.infinity < candidate.score {
                bestByState[key] = candidate
            }
        }
        return bestByState.values.sorted {
            $0.score == $1.score ? $0.lineageID < $1.lineageID : $0.score > $1.score
        }.prefix(Configuration.beamWidth).map { $0 }
    }

    /// Produces globally located candidates supported by several recent observations.
    private func recoveryHypotheses(
        for latestPitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp
    ) -> [Hypothesis] {
        // The newest pitch anchors candidate endings. Nearby backward alignment then
        // favors locations supported by the full observation suffix, not just one pitch.
        var candidates: [RecoveryCandidate] = []
        for momentIndex in momentsByPitch[latestPitch, default: []] {
            let evidence = recoveryEvidence(endingAt: momentIndex)
            guard evidence.exactMatches >= 2 else { continue }
            candidates.append(RecoveryCandidate(
                momentIndex: momentIndex,
                exactMatches: evidence.exactMatches,
                matchedMoments: evidence.moments
            ))
        }
        candidates.sort {
            $0.exactMatches == $1.exactMatches
                ? $0.momentIndex < $1.momentIndex
                : $0.exactMatches > $1.exactMatches
        }

        return candidates.prefix(Configuration.recoveryHypothesisLimit).map { candidate in
            let lineageID = nextLineageID
            nextLineageID += 1
            return Hypothesis(
                momentIndex: candidate.momentIndex,
                matchedPitches: [latestPitch],
                releasedPitches: [],
                score: Configuration.exactMatchReward * Double(candidate.exactMatches) * velocityWeight(for: velocity)
                    - Configuration.jumpPenalty,
                recentExactMatches: candidate.exactMatches,
                recentlyMatchedMoments: candidate.matchedMoments,
                lineageID: lineageID,
                isRecovery: true,
                momentStartedAt: valid(timestamp) ? timestamp : nil,
                lastMatchedAt: valid(timestamp) ? timestamp : nil,
                ticksPerBeat: nil
            )
        }
    }

    /// Matches the observation suffix backwards in a small reference neighbourhood.
    private func recoveryEvidence(endingAt index: Int) -> (exactMatches: Int, moments: Set<Int>) {
        var cursor = index
        var exactMatches = 0
        var matchedMoments: Set<Int> = []

        for pitch in observations.reversed() {
            guard cursor >= 0 else { break }
            if moments[cursor].pitches.contains(pitch) {
                exactMatches += 1
                matchedMoments.insert(cursor)
                cursor -= 1
            } else if cursor > 0, moments[cursor - 1].pitches.contains(pitch) {
                exactMatches += 1
                matchedMoments.insert(cursor - 1)
                cursor -= 2
            }
        }
        return (exactMatches, matchedMoments)
    }

    /// Selects the committed lineage and applies hysteresis before accepting a recovery.
    private func commitPosition() -> Position? {
        guard let committed = bestCommittedHypothesis else { return nil }

        if let recovery = hypotheses
            .filter({ $0.isRecovery })
            .sorted(by: { $0.score > $1.score })
            .first,
           canCommit(recovery: recovery, over: committed) {
            if recoveryWinningLineageID == recovery.lineageID {
                recoveryWinningStreak += 1
            } else {
                recoveryWinningLineageID = recovery.lineageID
                recoveryWinningStreak = 1
            }

            if recoveryWinningStreak >= Configuration.recoveryWinningStreak {
                committedLineageID = recovery.lineageID
                hypotheses = hypotheses.map {
                    guard $0.lineageID == recovery.lineageID else { return $0 }
                    var promoted = $0
                    promoted.isRecovery = false
                    return promoted
                }
                recoveryWinningLineageID = nil
                recoveryWinningStreak = 0
                return makePosition(from: recovery, didJump: true)
            }
        } else {
            recoveryWinningLineageID = nil
            recoveryWinningStreak = 0
        }

        return makePosition(from: committed, didJump: false)
    }

    private var bestCommittedHypothesis: Hypothesis? {
        hypotheses
            .filter { $0.lineageID == committedLineageID }
            .max { $0.score < $1.score }
    }

    /// Requires sustained, multi-moment evidence before a remote lineage can replace continuity.
    private func canCommit(recovery: Hypothesis, over committed: Hypothesis) -> Bool {
        recovery.recentExactMatches >= Configuration.recoveryExactMatches &&
        recovery.recentlyMatchedMoments.count >= Configuration.recoveryDistinctMoments &&
        recovery.score >= committed.score + Configuration.recoveryScoreLead
    }

    /// Computes certainty from a materially different competing lineage.
    private func makePosition(from hypothesis: Hypothesis, didJump: Bool) -> Position? {
        guard hypothesis.momentIndex >= 0 else { return nil }

        let alternative = hypotheses
            .filter { $0.lineageID != hypothesis.lineageID }
            .max { $0.score < $1.score }
        let confidence: Double
        if let alternative {
            let gap = hypothesis.score - alternative.score
            confidence = 1 / (1 + Foundation.exp(-gap / 3))
        } else {
            confidence = min(0.9, 0.5 + 0.08 * Double(hypothesis.recentExactMatches))
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
