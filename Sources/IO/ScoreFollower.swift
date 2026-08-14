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

    private struct ReferenceMoment {
        let beat: Double
        var pitches: Set<UInt8>
    }

    private struct Hypothesis {
        var momentIndex: Int
        var matchedPitches: Set<UInt8>
        var score: Double
        var recentExactMatches: Int
        var recentlyMatchedMoments: Set<Int>
        var lineageID: Int
        var isRecovery: Bool
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
    }

    /// Reference notes in their supplied form. Alignment uses a sorted, chord-grouped copy.
    public let reference: [ReferenceNote]

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
    public init(reference: [ReferenceNote]) {
        self.reference = reference
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
            grouped[grouped.count - 1].pitches.insert(note.pitch)
        }
        moments = grouped

        var index: [UInt8: [Int]] = [:]
        for (momentIndex, moment) in grouped.enumerated() {
            for pitch in moment.pitches {
                index[pitch, default: []].append(momentIndex)
            }
        }
        momentsByPitch = index
        reset()
    }

    /// Consumes one MIDI message and returns the currently inferred position.
    ///
    /// Only nonzero-velocity note-on messages affect alignment; all other messages,
    /// including note-offs and MIDI 2.0 packets, are ignored.
    public func consume(_ message: MIDIUniversalMessage) -> Position? {
        guard let pitch = noteOnPitch(from: message) else { return nil }
        return consume(noteOn: pitch)
    }

    /// Consumes a decoded nonzero-velocity note-on pitch.
    ///
    /// This internal entry point keeps alignment independent of Core MIDI packet decoding
    /// and supports deterministic package-level verification.
    func consume(noteOn pitch: UInt8) -> Position? {
        guard !moments.isEmpty else { return nil }

        acceptedNoteCount += 1
        observations.append(pitch)
        if observations.count > Configuration.observationLimit {
            observations.removeFirst()
        }

        let expanded = hypotheses.flatMap { expand($0, with: pitch) }
        hypotheses = prune(expanded)

        if shouldAttemptRecovery {
            hypotheses = prune(hypotheses + recoveryHypotheses(for: pitch))
        }

        return commitPosition()
    }

    /// Restores the follower to the state before the first reference moment.
    public func reset() {
        hypotheses = [Hypothesis(
            momentIndex: -1,
            matchedPitches: [],
            score: 0,
            recentExactMatches: 0,
            recentlyMatchedMoments: [],
            lineageID: 0,
            isRecovery: false
        )]
        observations.removeAll(keepingCapacity: true)
        acceptedNoteCount = 0
        committedLineageID = 0
        nextLineageID = 1
        recoveryWinningLineageID = nil
        recoveryWinningStreak = 0
        lastPosition = nil
    }

    /// Extracts MIDI 1.0 UMP note-ons while keeping packet decoding out of the aligner.
    private func noteOnPitch(from message: MIDIUniversalMessage) -> UInt8? {
        // `MIDIUniversalMessage` is an inline UMP word container. Reading its first
        // word by layout keeps this decoding compatible with the SDK's C-imported type.
        let word = withUnsafeBytes(of: message) { $0.load(as: UInt32.self) }
        let messageType = UInt8((word >> 28) & 0x0F)
        guard messageType == 0x2 else { return nil }

        let status = UInt8((word >> 16) & 0xFF)
        let pitch = UInt8((word >> 8) & 0x7F)
        let velocity = UInt8(word & 0x7F)
        guard status & 0xF0 == 0x90, velocity > 0 else { return nil }
        return pitch
    }

    private var shouldAttemptRecovery: Bool {
        guard !observations.isEmpty else { return false }
        guard acceptedNoteCount.isMultiple(of: Configuration.recoveryInterval) else {
            return bestCommittedHypothesis?.score ?? 0 < -4
        }
        return true
    }

    /// Creates bounded local interpretations of one performed pitch from an existing state.
    private func expand(_ hypothesis: Hypothesis, with pitch: UInt8) -> [Hypothesis] {
        var base = hypothesis
        base.score *= Configuration.scoreDecay

        var expansions: [Hypothesis] = []
        if base.momentIndex >= 0,
           moments[base.momentIndex].pitches.contains(pitch),
           !base.matchedPitches.contains(pitch) {
            expansions.append(match(pitch, in: base.momentIndex, from: base))
        }

        var extra = base
        extra.score -= Configuration.extraPerformedNotePenalty
        expansions.append(extra)

        let firstTarget = max(0, base.momentIndex + 1)
        let lastTarget = min(moments.count - 1, base.momentIndex + Configuration.localLookAhead)
        guard firstTarget <= lastTarget else { return expansions }

        for target in firstTarget...lastTarget {
            if moments[target].pitches.contains(pitch) {
                var advanced = advance(base, to: target)
                advanced = match(pitch, in: target, from: advanced)
                expansions.append(advanced)
            }
        }

        // A substitution advances one moment even when the pitch is wrong, avoiding a
        // permanent stall after a single wrong note.
        let substitutionTarget = max(0, base.momentIndex + 1)
        if substitutionTarget < moments.count {
            var substitution = advance(base, to: substitutionTarget)
            substitution.score -= Configuration.substitutionPenalty
            expansions.append(substitution)
        }
        return expansions
    }

    /// Applies the missing-note costs incurred when advancing between reference moments.
    private func advance(_ hypothesis: Hypothesis, to target: Int) -> Hypothesis {
        var advanced = hypothesis
        let firstOmitted = max(0, hypothesis.momentIndex)
        if firstOmitted < target {
            for index in firstOmitted..<target {
                let alreadyMatched = index == hypothesis.momentIndex ? hypothesis.matchedPitches : []
                advanced.score -= Configuration.unmatchedPitchPenalty * Double(moments[index].pitches.subtracting(alreadyMatched).count)
                advanced.score -= Configuration.completelySkippedMomentPenalty
            }
        }
        advanced.momentIndex = target
        advanced.matchedPitches = []
        return advanced
    }

    /// Records an exact pitch match and retains only recent, bounded jump evidence.
    private func match(_ pitch: UInt8, in momentIndex: Int, from hypothesis: Hypothesis) -> Hypothesis {
        var matched = hypothesis
        matched.momentIndex = momentIndex
        matched.matchedPitches.insert(pitch)
        matched.score += Configuration.exactMatchReward
        matched.recentExactMatches = min(Configuration.observationLimit, matched.recentExactMatches + 1)
        matched.recentlyMatchedMoments.insert(momentIndex)
        if matched.recentlyMatchedMoments.count > 6,
           let oldest = matched.recentlyMatchedMoments.min() {
            matched.recentlyMatchedMoments.remove(oldest)
        }
        return matched
    }

    /// Keeps only the strongest representative of each alignment state.
    private func prune(_ candidates: [Hypothesis]) -> [Hypothesis] {
        var bestByState: [String: Hypothesis] = [:]
        for candidate in candidates {
            let pitches = candidate.matchedPitches.sorted().map(String.init).joined(separator: ",")
            let key = "\(candidate.momentIndex)|\(pitches)|\(candidate.lineageID)"
            if bestByState[key]?.score ?? -.infinity < candidate.score {
                bestByState[key] = candidate
            }
        }
        return bestByState.values.sorted {
            $0.score == $1.score ? $0.lineageID < $1.lineageID : $0.score > $1.score
        }.prefix(Configuration.beamWidth).map { $0 }
    }

    /// Produces globally located candidates supported by several recent observations.
    private func recoveryHypotheses(for latestPitch: UInt8) -> [Hypothesis] {
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
                score: Configuration.exactMatchReward * Double(candidate.exactMatches) - Configuration.jumpPenalty,
                recentExactMatches: candidate.exactMatches,
                recentlyMatchedMoments: candidate.matchedMoments,
                lineageID: lineageID,
                isRecovery: true
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
