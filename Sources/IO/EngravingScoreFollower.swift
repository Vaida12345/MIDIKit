//
//  EngravingScoreFollower.swift
//  MIDIKit
//
//  Created by Vaida on 2026-09-03.
//

import CoreMIDI
import Foundation


/// An immutable score and engraving-layout reference used by ``EngravingScoreFollower``.
///
/// Unlike the pitch-only reference accepted by ``ScoreFollower``, this reference retains
/// measure, system-line, hand, duration, and attack information. Replacing the reference
/// replaces both the musical and layout state as one atomic operation.
public struct EngravingReference: Sendable, Hashable {

    /// The notated hand responsible for a reference note.
    public enum Hand: UInt8, Sendable, Hashable, CaseIterable {
        case left
        case right
    }

    /// How pitches sharing a score onset are expected to be attacked.
    public enum Attack: UInt8, Sendable, Hashable {
        /// The pitches form one block-chord gesture.
        case block

        /// The pitches form one deliberately spread gesture.
        case rolled
    }

    /// A note expected at one reference moment.
    public struct Note: Sendable, Hashable {
        /// MIDI note number in `0...127`.
        public let pitch: UInt8

        /// Written duration in beats.
        public let duration: Double

        /// The notated hand.
        public let hand: Hand

        public init(pitch: UInt8, duration: Double, hand: Hand) {
            self.pitch = pitch
            self.duration = duration
            self.hand = hand
        }
    }

    /// A collection of reference notes sharing one notated onset.
    public struct Moment: Sendable, Hashable {
        /// Onset in score beats.
        public let beat: Double

        /// Notes expected at this onset.
        public let notes: [Note]

        /// The expected attack style.
        public let attack: Attack

        public init(beat: Double, notes: [Note], attack: Attack = .block) {
            self.beat = beat
            self.notes = notes
            self.attack = attack
        }
    }

    /// A notated measure.
    public struct Measure: Sendable, Hashable {
        /// Stable measure number or index supplied by the engraving model.
        public let index: Int

        /// Measure onset in score beats.
        public let onset: Double

        /// Measure duration in beats.
        public let duration: Double

        /// Complete beat range occupied by the measure.
        public var beatRange: ClosedRange<Double> {
            onset...(onset + duration)
        }

        public init(index: Int, onset: Double, duration: Double) {
            self.index = index
            self.onset = onset
            self.duration = duration
        }
    }

    /// One engraved system line.
    public struct Line: Sendable, Hashable {
        /// Stable line number or index supplied by the engraving model.
        public let index: Int

        /// Score beats displayed by the line.
        public let beatRange: ClosedRange<Double>

        /// Measure indices displayed by the line.
        public let measureRange: ClosedRange<Int>

        public init(
            index: Int,
            beatRange: ClosedRange<Double>,
            measureRange: ClosedRange<Int>
        ) {
            self.index = index
            self.beatRange = beatRange
            self.measureRange = measureRange
        }
    }

    /// A malformed engraving reference.
    public enum ValidationError: Error, LocalizedError, Sendable, Hashable {
        case emptyMeasures
        case emptyLines
        case emptyMoments
        case duplicateMeasureIndex(Int)
        case duplicateLineIndex(Int)
        case invalidMeasure(Int)
        case nonIncreasingMeasureIndex(Int)
        case invalidLine(Int)
        case measureWithoutLine(Int)
        case invalidMoment(Double)
        case momentOutsideMeasures(Double)
        case invalidNote(pitch: UInt8, beat: Double)

        public var errorDescription: String? {
            switch self {
            case .emptyMeasures:
                "An engraving reference must contain at least one measure."
            case .emptyLines:
                "An engraving reference must contain at least one line."
            case .emptyMoments:
                "An engraving reference must contain at least one musical moment."
            case let .duplicateMeasureIndex(index):
                "Measure index \(index) occurs more than once."
            case let .duplicateLineIndex(index):
                "Line index \(index) occurs more than once."
            case let .invalidMeasure(index):
                "Measure \(index) must have a finite onset and a finite, positive duration."
            case let .nonIncreasingMeasureIndex(index):
                "Measure index \(index) is not greater than the preceding measure index."
            case let .invalidLine(index):
                "Line \(index) has an invalid beat or measure range."
            case let .measureWithoutLine(index):
                "Measure \(index) does not belong to exactly one engraving line."
            case let .invalidMoment(beat):
                "The reference moment at beat \(beat) is empty or invalid."
            case let .momentOutsideMeasures(beat):
                "The reference moment at beat \(beat) does not belong to a measure."
            case let .invalidNote(pitch, beat):
                "Pitch \(pitch) at beat \(beat) is outside MIDI 1.0 or has an invalid duration."
            }
        }
    }

    /// Measures ordered by onset.
    public let measures: [Measure]

    /// Engraving lines ordered by their lower beat bound.
    public let lines: [Line]

    /// Musical moments ordered and normalized by onset.
    public let moments: [Moment]

    /// Creates and validates a complete score-and-layout reference.
    ///
    /// Moments with effectively identical onsets are merged. Repeated note metadata for the
    /// same pitch and hand is reduced to the longest written duration, and a merged moment is
    /// treated as rolled when any source moment is rolled.
    public init(
        measures: [Measure],
        lines: [Line],
        moments: [Moment]
    ) throws {
        guard !measures.isEmpty else { throw ValidationError.emptyMeasures }
        guard !lines.isEmpty else { throw ValidationError.emptyLines }
        guard !moments.isEmpty else { throw ValidationError.emptyMoments }

        let sortedMeasures = measures.sorted {
            $0.onset == $1.onset ? $0.index < $1.index : $0.onset < $1.onset
        }
        var measureIndices = Set<Int>()
        measureIndices.reserveCapacity(sortedMeasures.count)
        for measure in sortedMeasures {
            guard measure.onset.isFinite,
                  measure.duration.isFinite,
                  measure.duration > 0 else {
                throw ValidationError.invalidMeasure(measure.index)
            }
            guard measureIndices.insert(measure.index).inserted else {
                throw ValidationError.duplicateMeasureIndex(measure.index)
            }
        }
        for index in 1..<sortedMeasures.count {
            let previous = sortedMeasures[index - 1]
            let current = sortedMeasures[index]
            guard current.onset >= previous.onset + previous.duration - Self.simultaneousBeatEpsilon else {
                throw ValidationError.invalidMeasure(current.index)
            }
            guard current.index > previous.index else {
                throw ValidationError.nonIncreasingMeasureIndex(current.index)
            }
        }

        let sortedLines = lines.sorted {
            $0.beatRange.lowerBound == $1.beatRange.lowerBound
                ? $0.index < $1.index
                : $0.beatRange.lowerBound < $1.beatRange.lowerBound
        }
        var lineIndices = Set<Int>()
        lineIndices.reserveCapacity(sortedLines.count)
        for line in sortedLines {
            guard line.beatRange.lowerBound.isFinite,
                  line.beatRange.upperBound.isFinite else {
                throw ValidationError.invalidLine(line.index)
            }
            guard lineIndices.insert(line.index).inserted else {
                throw ValidationError.duplicateLineIndex(line.index)
            }
        }

        for line in sortedLines {
            guard sortedMeasures.contains(where: { $0.index == line.measureRange.lowerBound }),
                  sortedMeasures.contains(where: { $0.index == line.measureRange.upperBound }) else {
                throw ValidationError.invalidLine(line.index)
            }
        }

        for measure in sortedMeasures {
            let containingLines = sortedLines.filter {
                $0.measureRange.contains(measure.index)
            }
            guard containingLines.count == 1 else {
                throw ValidationError.measureWithoutLine(measure.index)
            }
            guard let line = containingLines.first,
                  line.beatRange.lowerBound <= measure.onset + Self.simultaneousBeatEpsilon,
                  line.beatRange.upperBound + Self.simultaneousBeatEpsilon
                    >= measure.onset + measure.duration else {
                throw ValidationError.invalidLine(containingLines.first?.index ?? -1)
            }
        }

        let normalizedMoments = try Self.normalize(moments)
        for moment in normalizedMoments {
            guard Self.measureOffset(containing: moment.beat, in: sortedMeasures) != nil else {
                throw ValidationError.momentOutsideMeasures(moment.beat)
            }
        }

        self.measures = sortedMeasures
        self.lines = sortedLines
        self.moments = normalizedMoments
    }

    fileprivate static let simultaneousBeatEpsilon = 1e-6

    private static func normalize(_ moments: [Moment]) throws -> [Moment] {
        let sorted = moments.sorted { lhs, rhs in
            lhs.beat == rhs.beat ? lhs.notes.count < rhs.notes.count : lhs.beat < rhs.beat
        }
        var result: [Moment] = []
        result.reserveCapacity(sorted.count)

        for moment in sorted {
            guard moment.beat.isFinite, !moment.notes.isEmpty else {
                throw ValidationError.invalidMoment(moment.beat)
            }
            for note in moment.notes {
                guard note.pitch < 128,
                      note.duration.isFinite,
                      note.duration >= 0 else {
                    throw ValidationError.invalidNote(pitch: note.pitch, beat: moment.beat)
                }
            }

            guard let previous = result.last,
                  abs(previous.beat - moment.beat) <= simultaneousBeatEpsilon else {
                result.append(Self.normalized(moment))
                continue
            }

            var notes = previous.notes + moment.notes
            notes = Self.normalizedNotes(notes)
            result[result.count - 1] = Moment(
                beat: previous.beat,
                notes: notes,
                attack: previous.attack == .rolled || moment.attack == .rolled ? .rolled : .block
            )
        }
        return result
    }

    private static func normalized(_ moment: Moment) -> Moment {
        Moment(
            beat: moment.beat,
            notes: normalizedNotes(moment.notes),
            attack: moment.attack
        )
    }

    private struct NoteKey: Hashable {
        let pitch: UInt8
        let hand: Hand
    }

    private static func normalizedNotes(_ notes: [Note]) -> [Note] {
        var longestDuration: [NoteKey: Double] = [:]
        longestDuration.reserveCapacity(notes.count)
        for note in notes {
            let key = NoteKey(pitch: note.pitch, hand: note.hand)
            longestDuration[key] = max(longestDuration[key] ?? 0, note.duration)
        }
        return longestDuration.map { key, duration in
            Note(pitch: key.pitch, duration: duration, hand: key.hand)
        }.sorted {
            $0.pitch == $1.pitch ? $0.hand.rawValue < $1.hand.rawValue : $0.pitch < $1.pitch
        }
    }

    /// Finds a measure using half-open boundaries except at the end of the final measure.
    fileprivate static func measureOffset(containing beat: Double, in measures: [Measure]) -> Int? {
        guard beat.isFinite else { return nil }
        var lower = 0
        var upper = measures.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if measures[middle].onset <= beat + simultaneousBeatEpsilon {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        let candidate = max(0, lower - 1)
        guard measures.indices.contains(candidate) else { return nil }
        let measure = measures[candidate]
        guard beat >= measure.onset - simultaneousBeatEpsilon,
              beat <= measure.onset + measure.duration + simultaneousBeatEpsilon else {
            return nil
        }
        return candidate
    }
}


/// A score follower specialized for an engraving-driven piano-practice interface.
///
/// This follower treats backward practice as a separately confirmed replay, automatically
/// infers left-, right-, or both-hand participation, and keeps uncertain musical inference from
/// moving the performer's visual frame. The viewport advances by one engraving line during
/// continuous playing and can otherwise move only as part of a confirmed jump.
///
/// Start a performance epoch by calling ``reset()``, assign ``visibleRange`` as often as the
/// scroll view changes, then pass MIDI events to ``consume(_:)``. The first informative note-on
/// latches the latest post-reset visible range as an acquisition hint. Subsequent visible-range
/// changes bound local replay but cannot reinforce the inferred musical position.
///
/// See `Documentation/EngravingScoreFollower.md` for the complete integration contract and
/// performer-facing invariants.
public final class EngravingScoreFollower {

    /// Whether the performance is using one or both notated hands.
    public enum HandParticipation: UInt8, Sendable, Hashable {
        case unknown
        case left
        case right
        case both
    }

    /// The public stability state of the inferred location.
    public enum TrackingState: UInt8, Sendable, Hashable {
        case acquiring
        case tracking
        case uncertain
        case lost
    }

    /// A rare, stable viewport instruction for the engraving application.
    public enum ViewportRecommendation: Sendable, Hashable {
        /// Preserve the current scroll position.
        case unchanged

        /// Center the immediately following engraving line.
        ///
        /// Applications should render this as one short, non-springing line movement. It is
        /// emitted only after the performance has been committed to that line, never in
        /// anticipation of an approaching line ending.
        case advance(toLine: Int)

        /// Reframe the score at a nonlocal destination.
        ///
        /// A jump may move in either direction. Applications should snap or crossfade to the
        /// destination rather than animate through intervening music.
        case jump(toLine: Int)
    }

    /// One score-following result.
    public struct Update: Sendable, Hashable {
        /// Committed current musical position, in score beats.
        public let beat: Double

        /// Stable beat intended for the application's visible position marker.
        ///
        /// During a performance epoch this value never decreases during ordinary tracking or a
        /// visible replay. It can move backward only when ``didRelocate`` is `true`.
        public let displayBeat: Double

        /// Nearby beats that remain musically plausible in the committed local region.
        public let plausibleBeatRange: ClosedRange<Double>

        /// Engraving measure containing ``beat``.
        public let measureIndex: Int

        /// Position certainty from zero through one.
        public let confidence: Double

        /// Alignment stability.
        public let state: TrackingState

        /// Inferred performed hand participation.
        public let activeHands: HandParticipation

        /// An occasional, performer-safe request to change the engraving viewport.
        public let viewport: ViewportRecommendation

        /// Whether this result committed a discontinuous presentation jump.
        ///
        /// When this is `true`, ``displayBeat`` may move in either direction and ``viewport``
        /// is ``ViewportRecommendation/jump(toLine:)``.
        public let didRelocate: Bool
    }

    /// The current complete score-and-layout reference.
    public private(set) var reference: EngravingReference?

    /// The beat range currently displayed by the scroll view.
    ///
    /// After ``reset()``, assignments update the pending acquisition hint until the first
    /// note-on. During tracking, assignments define the perceptual boundary between a local
    /// replay and a nonlocal jump; they never add evidence to a score-position hypothesis.
    public var visibleRange: ClosedRange<Double>? {
        didSet {
            guard phase == .awaitingPerformance else { return }
            pendingAcquisitionRange = Self.validRange(visibleRange)
        }
    }

    /// Most recently returned result.
    public private(set) var lastUpdate: Update?

    public init() {}

    /// Atomically replaces the musical and engraving-layout reference and starts a new
    /// viewport-sampling acquisition epoch.
    public func update(reference: EngravingReference) async {
        self.reference = reference
        compiled = CompiledReference(reference)
        reset()
    }

    /// Clears alignment and waits for post-reset viewport updates followed by performance.
    public func reset() {
        phase = .awaitingPerformance
        pendingAcquisitionRange = nil
        acquisitionMeasureOffsets = nil
        primaryHypotheses.removeAll(keepingCapacity: true)
        replayHypotheses.removeAll(keepingCapacity: true)
        relocationHypotheses.removeAll(keepingCapacity: true)
        sustainIsDown = false
        sostenutoIsDown = false
        poorEvidenceStreak = 0
        relocationWinningStreak = 0
        lastRelocationWinningGestureCount = 0
        lastCommittedGestureCount = 0
        recentObservedGestures.removeAll(keepingCapacity: true)
        inferredParticipation = .unknown
        leftParticipationEvidence = 0
        rightParticipationEvidence = 0
        committedMomentIndex = nil
        displayMomentIndex = nil
        viewportLineOffset = nil
        lastUpdate = nil
    }

    /// Consumes one event published by ``MIDIInputController``.
    public func consume(_ input: MIDIInputEvent) -> Update? {
        switch input.event {
        case let .noteOn(pitch, velocity):
            return consume(noteOn: pitch, velocity: velocity, timestamp: input.timestamp)
        case let .noteOff(pitch):
            consume(noteOff: pitch)
            return nil
        case let .controlChange(control, value):
            consume(controlChange: control, value: value)
            return nil
        }
    }

    // MARK: - Internal model

    private enum Phase {
        case awaitingPerformance
        case acquiring
        case tracking
        case lost
    }

    private enum ParticipationMode: UInt8, CaseIterable, Hashable {
        case both
        case left
        case right
    }

    private enum CandidateKind: UInt8, Hashable {
        case primary
        case replay
        case relocation
    }

    private struct CompiledMoment {
        let beat: Double
        let measureOffset: Int
        let lineOffset: Int
        let attack: EngravingReference.Attack
        let allPitchMask: UInt128
        let leftPitchMask: UInt128
        let rightPitchMask: UInt128
        let averageDuration: SIMD3<Double>
        var distinctiveness: SIMD3<Double>

        func pitchMask(for mode: ParticipationMode) -> UInt128 {
            switch mode {
            case .both: allPitchMask
            case .left: leftPitchMask
            case .right: rightPitchMask
            }
        }
    }

    private struct CompiledReference {
        let measures: [EngravingReference.Measure]
        let lines: [EngravingReference.Line]
        let moments: [CompiledMoment]
        let momentsByPitch: [[[Int]]]
        let lineOffsetByMeasureOffset: [Int]

        init(_ reference: EngravingReference) {
            measures = reference.measures
            lines = reference.lines

            var lineByMeasure = Array(repeating: 0, count: reference.measures.count)
            for (measureOffset, measure) in reference.measures.enumerated() {
                lineByMeasure[measureOffset] = reference.lines.firstIndex {
                    $0.measureRange.contains(measure.index)
                } ?? 0
            }
            lineOffsetByMeasureOffset = lineByMeasure

            var compiledMoments: [CompiledMoment] = []
            compiledMoments.reserveCapacity(reference.moments.count)
            for moment in reference.moments {
                guard let measureOffset = EngravingReference.measureOffset(
                    containing: moment.beat,
                    in: reference.measures
                ) else {
                    continue
                }

                var allMask: UInt128 = 0
                var leftMask: UInt128 = 0
                var rightMask: UInt128 = 0
                var allDuration = 0.0
                var leftDuration = 0.0
                var rightDuration = 0.0
                var leftCount = 0
                var rightCount = 0
                for note in moment.notes {
                    let mask = EngravingScoreFollower.pitchMask(for: note.pitch)
                    allMask |= mask
                    allDuration += note.duration
                    switch note.hand {
                    case .left:
                        leftMask |= mask
                        leftDuration += note.duration
                        leftCount += 1
                    case .right:
                        rightMask |= mask
                        rightDuration += note.duration
                        rightCount += 1
                    }
                }
                compiledMoments.append(CompiledMoment(
                    beat: moment.beat,
                    measureOffset: measureOffset,
                    lineOffset: lineByMeasure[measureOffset],
                    attack: moment.attack,
                    allPitchMask: allMask,
                    leftPitchMask: leftMask,
                    rightPitchMask: rightMask,
                    averageDuration: SIMD3(
                        allDuration / Double(max(1, moment.notes.count)),
                        leftDuration / Double(max(1, leftCount)),
                        rightDuration / Double(max(1, rightCount))
                    ),
                    distinctiveness: .zero
                ))
            }

            var pitchIndex = Array(
                repeating: Array(repeating: [Int](), count: 128),
                count: ParticipationMode.allCases.count
            )
            for (momentIndex, moment) in compiledMoments.enumerated() {
                for mode in ParticipationMode.allCases {
                    var remainingPitches = moment.pitchMask(for: mode)
                    while remainingPitches != 0 {
                        let pitch = remainingPitches.trailingZeroBitCount
                        pitchIndex[Int(mode.rawValue)][pitch].append(momentIndex)
                        remainingPitches &= remainingPitches - 1
                    }
                }
            }

            Self.assignDistinctiveness(to: &compiledMoments, momentsByPitch: pitchIndex)
            moments = compiledMoments
            momentsByPitch = pitchIndex
        }

        private static func assignDistinctiveness(
            to moments: inout [CompiledMoment],
            momentsByPitch: [[[Int]]]
        ) {
            guard !moments.isEmpty else { return }
            let scoreCount = Double(moments.count)
            for momentIndex in moments.indices {
                var values = SIMD3<Double>.zero
                for mode in ParticipationMode.allCases {
                    var remainingPitches = moments[momentIndex].pitchMask(for: mode)
                    guard remainingPitches != 0 else { continue }
                    var information = 0.0
                    var pitchCount = 0
                    while remainingPitches != 0 {
                        let pitch = remainingPitches.trailingZeroBitCount
                        let occurrences = max(
                            1,
                            momentsByPitch[Int(mode.rawValue)][pitch].count
                        )
                        information += Foundation.log1p(scoreCount / Double(occurrences))
                        pitchCount += 1
                        remainingPitches &= remainingPitches - 1
                    }
                    let normalized = information / Double(max(1, pitchCount))
                    values[Int(mode.rawValue)] = min(1, normalized / Foundation.log1p(scoreCount))
                }
                moments[momentIndex].distinctiveness = values
            }
        }
    }

    private struct Hypothesis {
        var momentIndex: Int
        var mode: ParticipationMode
        var kind: CandidateKind
        var performedPitchMask: UInt128
        var releasedPitchMask: UInt128
        var score: Double
        var gestureStartedAt: MIDITimeStamp?
        var lastNoteOnAt: MIDITimeStamp?
        var ticksPerBeat: Double?
        var intraGestureTicks: Double?
        var gestureCount: Int
        var evidenceEventCount: Int
        var mismatchLoad: Double
        var probeEvidence: Double
        var seedMomentIndex: Int
        var lastCompletedGestureMask: UInt128
    }

    private struct HypothesisState: Hashable {
        let momentIndex: Int
        let mode: ParticipationMode
        let kind: CandidateKind
        let performedPitchMask: UInt128
        let releasedPitchMask: UInt128
        let gestureCount: Int
    }

    private struct PositionKey: Hashable {
        let momentIndex: Int
    }

    private struct PositionScore {
        let momentIndex: Int
        var score: Double
    }

    private enum Configuration {
        static let beamWidth = 48
        static let replayBeamWidth = 18
        static let relocationBeamWidth = 24
        static let maximumForwardTargets = 7
        static let maximumReplaySeedsPerMode = 8
        static let maximumRelocationSeedsPerMode = 10
        static let scoreMemory = 0.985
        static let fullGestureReward = 5.0
        static let supplementalHandReward = 0.0
        static let wrongPitchPenalty = 1.35
        static let repeatedWithoutReleasePenalty = 1.8
        static let missingGesturePenalty = 2.6
        static let substitutionPenalty = 2.2
        static let incompleteBoundaryPenalty = 2.0
        static let adjacentMeasurePenalty = 0.7
        static let skippedMomentPenalty = 0.55
        static let replaySeedPenalty = 5.0
        static let replayCommitLead = 2.75
        static let replayEvidenceRequired = 1.35
        static let relocationSeedPenalty = 7.5
        static let acquisitionReseedPenalty = 12.0
        static let relocationCommitLead = 4.0
        static let relocationEvidenceRequired = 2.4
        static let relocationActivationLoad = 3.0
        static let poorEvidenceToRelocate = 4.5
        static let poorEvidenceEventsToRelocate = 3
        static let acquisitionPrior = 3.5
        static let adjacentAcquisitionPrior = 1.25
        static let acquisitionEvidenceToTrack = 2
        static let plausibleScoreWindow = 3.25
        static let confidenceScale = 2.25
        static let maximumRecentGestures = 5
    }

    private var compiled: CompiledReference?
    private var phase: Phase = .awaitingPerformance
    private var pendingAcquisitionRange: ClosedRange<Double>?
    private var acquisitionMeasureOffsets: ClosedRange<Int>?
    private var primaryHypotheses: [Hypothesis] = []
    private var replayHypotheses: [Hypothesis] = []
    private var relocationHypotheses: [Hypothesis] = []
    private var sustainIsDown = false
    private var sostenutoIsDown = false
    private var poorEvidenceStreak = 0
    private var relocationWinningStreak = 0
    private var lastRelocationWinningGestureCount = 0
    private var lastCommittedGestureCount = 0
    private var recentObservedGestures: [UInt128] = []
    private var inferredParticipation: HandParticipation = .unknown
    private var leftParticipationEvidence = 0.0
    private var rightParticipationEvidence = 0.0
    private var committedMomentIndex: Int?
    private var displayMomentIndex: Int?
    private var viewportLineOffset: Int?

    // MARK: - Performance input

    /// Consumes a decoded note-on. This entry point also keeps deterministic package tests
    /// independent of Core MIDI packet construction.
    func consume(
        noteOn pitch: UInt8,
        velocity: UInt8 = 127,
        timestamp: MIDITimeStamp
    ) -> Update? {
        guard pitch < 128 else { return nil }
        guard velocity != 0 else {
            consume(noteOff: pitch)
            return nil
        }
        guard let compiled, !compiled.moments.isEmpty else {
            return nil
        }

        if phase == .awaitingPerformance {
            let occurrences = compiled.momentsByPitch[
                Int(ParticipationMode.both.rawValue)
            ][Int(pitch)]
            guard !occurrences.isEmpty else {
                return nil
            }
            beginAcquisition(using: compiled)
        }

        let previousPrimaryBest = primaryHypotheses.max(by: { $0.score < $1.score })
        if primaryHypotheses.isEmpty {
            primaryHypotheses = seedHypotheses(
                for: pitch,
                velocity: velocity,
                timestamp: timestamp,
                in: compiled
            )
            guard !primaryHypotheses.isEmpty else { return nil }
        } else {
            var expanded: [Hypothesis] = []
            expanded.reserveCapacity(
                primaryHypotheses.count * (2 + Configuration.maximumForwardTargets)
            )
            for hypothesis in primaryHypotheses {
                expand(
                    hypothesis,
                    with: pitch,
                    velocity: velocity,
                    timestamp: timestamp,
                    in: compiled,
                    into: &expanded
                )
            }

            if phase == .acquiring,
               let bestScore = expanded.max(by: { $0.score < $1.score })?.score {
                let reseeds = seedHypotheses(
                    for: pitch,
                    velocity: velocity,
                    timestamp: timestamp,
                    in: compiled,
                    scoreBase: bestScore - Configuration.acquisitionReseedPenalty
                )
                expanded.append(contentsOf: reseeds)
            }
            primaryHypotheses = prune(expanded, limit: Configuration.beamWidth, in: compiled)
        }

        if phase != .acquiring, let committedMomentIndex {
            primaryHypotheses.removeAll { $0.momentIndex < committedMomentIndex }
        }

        guard var bestPrimary = primaryHypotheses.max(by: { $0.score < $1.score }) else {
            return nil
        }

        var didReplay = false
        if phase != .acquiring, let previousPrimaryBest {
            updateReplay(
                with: pitch,
                velocity: velocity,
                timestamp: timestamp,
                previousPrimaryBest: previousPrimaryBest,
                primaryBest: bestPrimary,
                in: compiled
            )
            didReplay = commitReplayIfReady(primaryBest: bestPrimary, in: compiled)
            if didReplay,
               let promotedBest = primaryHypotheses.max(by: { $0.score < $1.score }) {
                bestPrimary = promotedBest
            }
        }

        poorEvidenceStreak = bestPrimary.mismatchLoad >= Configuration.poorEvidenceToRelocate
            ? poorEvidenceStreak + 1
            : max(0, poorEvidenceStreak - 1)

        if phase != .acquiring,
           bestPrimary.mismatchLoad >= Configuration.poorEvidenceToRelocate,
           poorEvidenceStreak >= Configuration.poorEvidenceEventsToRelocate {
            phase = .lost
        }

        let shouldEvaluateRelocation = !didReplay && (phase == .lost
            || (phase != .acquiring
                && bestPrimary.mismatchLoad >= Configuration.relocationActivationLoad))
        if shouldEvaluateRelocation {
            updateRelocationProbe(
                with: pitch,
                velocity: velocity,
                timestamp: timestamp,
                primaryBest: bestPrimary,
                in: compiled
            )
        } else {
            clearRelocationProbe()
        }

        let didRelocate = commitRelocationIfReady(primaryBest: bestPrimary, in: compiled)
        let effectiveBest = primaryHypotheses.max(by: { $0.score < $1.score }) ?? bestPrimary
        return makeUpdate(
            from: effectiveBest,
            observedPitch: pitch,
            didReplay: didReplay,
            didRelocate: didRelocate,
            in: compiled
        )
    }

    /// Records a physical key release without treating it as an independent score attack.
    func consume(noteOff pitch: UInt8) {
        guard pitch < 128 else { return }
        let mask = Self.pitchMask(for: pitch)
        for index in primaryHypotheses.indices
        where primaryHypotheses[index].performedPitchMask & mask != 0 {
            primaryHypotheses[index].releasedPitchMask |= mask
        }
        for index in replayHypotheses.indices
        where replayHypotheses[index].performedPitchMask & mask != 0 {
            replayHypotheses[index].releasedPitchMask |= mask
        }
        for index in relocationHypotheses.indices
        where relocationHypotheses[index].performedPitchMask & mask != 0 {
            relocationHypotheses[index].releasedPitchMask |= mask
        }
    }

    /// Records pedal state needed to distinguish physical releases from sounding notes.
    func consume(controlChange control: UInt8, value: UInt8) {
        switch control {
        case 64: sustainIsDown = value >= 64
        case 66: sostenutoIsDown = value >= 64
        default: break
        }
    }

    // MARK: - Acquisition

    private func beginAcquisition(using compiled: CompiledReference) {
        acquisitionMeasureOffsets = pendingAcquisitionRange.flatMap {
            measureOffsets(intersecting: $0, in: compiled)
        }
        phase = .acquiring
    }

    private struct SeedCandidate {
        let momentIndex: Int
        let mode: ParticipationMode
        let prior: Double
    }

    private struct SeedKey: Hashable {
        let momentIndex: Int
        let mode: ParticipationMode
    }

    private func seedHypotheses(
        for pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        in compiled: CompiledReference,
        scoreBase: Double = 0
    ) -> [Hypothesis] {
        var seeds: [SeedCandidate] = []
        seeds.reserveCapacity(Configuration.beamWidth * 2)

        for mode in ParticipationMode.allCases {
            let occurrences = compiled.momentsByPitch[Int(mode.rawValue)][Int(pitch)]
            guard !occurrences.isEmpty else { continue }

            var preferred: [SeedCandidate] = []
            preferred.reserveCapacity(min(occurrences.count, 24))
            for momentIndex in occurrences {
                let measureOffset = compiled.moments[momentIndex].measureOffset
                let prior: Double
                if acquisitionMeasureOffsets?.contains(measureOffset) == true {
                    prior = Configuration.acquisitionPrior
                } else if let acquisitionMeasureOffsets,
                          measureOffset >= acquisitionMeasureOffsets.lowerBound - 1,
                          measureOffset <= acquisitionMeasureOffsets.upperBound + 1 {
                    prior = Configuration.adjacentAcquisitionPrior
                } else {
                    prior = 0
                }
                preferred.append(SeedCandidate(
                    momentIndex: momentIndex,
                    mode: mode,
                    prior: prior + (mode == .both ? 0.15 : 0)
                ))
            }
            preferred.sort {
                if $0.prior != $1.prior { return $0.prior > $1.prior }
                let lhs = compiled.moments[$0.momentIndex].distinctiveness[Int(mode.rawValue)]
                let rhs = compiled.moments[$1.momentIndex].distinctiveness[Int(mode.rawValue)]
                return lhs == rhs ? $0.momentIndex < $1.momentIndex : lhs > rhs
            }
            seeds.append(contentsOf: preferred.prefix(16))

            // Preserve score-wide geographic coverage when acquisition has no useful viewport.
            let distributedCount = min(8, occurrences.count)
            if distributedCount > 0 {
                for index in 0..<distributedCount {
                    let offset = distributedCount == 1
                        ? 0
                        : Int(
                            (
                                Double(index) * Double(occurrences.count - 1)
                                / Double(distributedCount - 1)
                            ).rounded()
                        )
                    let momentIndex = occurrences[offset]
                    seeds.append(SeedCandidate(
                        momentIndex: momentIndex,
                        mode: mode,
                        prior: mode == .both ? 0.15 : 0
                    ))
                }
            }
        }

        var unique: [SeedKey: SeedCandidate] = [:]
        unique.reserveCapacity(seeds.count)
        for seed in seeds {
            let key = SeedKey(momentIndex: seed.momentIndex, mode: seed.mode)
            if unique[key]?.prior ?? -.infinity < seed.prior {
                unique[key] = seed
            }
        }

        let velocityWeight = self.velocityWeight(for: velocity)
        let seeded = unique.values.map { seed in
            let expected = compiled.moments[seed.momentIndex].pitchMask(for: seed.mode)
            let reward = exactPitchReward(expectedPitchMask: expected) * velocityWeight
            return Hypothesis(
                momentIndex: seed.momentIndex,
                mode: seed.mode,
                kind: .primary,
                performedPitchMask: Self.pitchMask(for: pitch),
                releasedPitchMask: 0,
                score: scoreBase + seed.prior + reward,
                gestureStartedAt: Self.valid(timestamp) ? timestamp : nil,
                lastNoteOnAt: Self.valid(timestamp) ? timestamp : nil,
                ticksPerBeat: nil,
                intraGestureTicks: nil,
                gestureCount: 0,
                evidenceEventCount: 1,
                mismatchLoad: 0,
                probeEvidence: 0,
                seedMomentIndex: seed.momentIndex,
                lastCompletedGestureMask: 0
            )
        }
        return prune(seeded, limit: Configuration.beamWidth, in: compiled)
    }

    private func measureOffsets(
        intersecting beatRange: ClosedRange<Double>,
        in compiled: CompiledReference
    ) -> ClosedRange<Int>? {
        var offsets: [Int] = []
        offsets.reserveCapacity(compiled.measures.count)
        let isPointSample = beatRange.upperBound - beatRange.lowerBound
            <= EngravingReference.simultaneousBeatEpsilon
        if isPointSample {
            if let offset = EngravingReference.measureOffset(
                containing: beatRange.lowerBound,
                in: compiled.measures
            ) {
                offsets.append(offset)
            }
        } else {
            for (offset, measure) in compiled.measures.enumerated() {
                if Self.hasPositiveOverlap(measure.beatRange, beatRange) {
                    offsets.append(offset)
                }
            }
        }

        // Expand to full engraving lines intersecting the sampled viewport.
        var lineOffsets = Set<Int>()
        if isPointSample {
            if let lineOffset = compiled.lines.lastIndex(where: {
                $0.beatRange.lowerBound <= beatRange.lowerBound
                    + EngravingReference.simultaneousBeatEpsilon
                    && $0.beatRange.upperBound
                    + EngravingReference.simultaneousBeatEpsilon >= beatRange.lowerBound
            }) {
                lineOffsets.insert(lineOffset)
            }
        } else {
            for (lineOffset, line) in compiled.lines.enumerated()
            where Self.hasPositiveOverlap(line.beatRange, beatRange) {
                lineOffsets.insert(lineOffset)
            }
        }
        if !lineOffsets.isEmpty {
            for (measureOffset, lineOffset) in compiled.lineOffsetByMeasureOffset.enumerated()
            where lineOffsets.contains(lineOffset) {
                offsets.append(measureOffset)
            }
        }

        guard let lower = offsets.min(), let upper = offsets.max() else { return nil }
        return lower...upper
    }

    // MARK: - Hypothesis expansion

    private func expand(
        _ hypothesis: Hypothesis,
        with pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        in compiled: CompiledReference,
        into expansions: inout [Hypothesis]
    ) {
        var base = hypothesis
        base.score *= Configuration.scoreMemory
        expansions.append(
            continuingGesture(
                base,
                with: pitch,
                velocity: velocity,
                timestamp: timestamp,
                in: compiled
            )
        )

        let targets = forwardTargets(
            from: base,
            matching: pitch,
            in: compiled
        )
        for target in targets {
            expansions.append(
                transitioning(
                    base,
                    to: target,
                    with: pitch,
                    velocity: velocity,
                    timestamp: timestamp,
                    in: compiled
                )
            )
        }
    }

    private func continuingGesture(
        _ hypothesis: Hypothesis,
        with pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        in compiled: CompiledReference
    ) -> Hypothesis {
        var continued = hypothesis
        let moment = compiled.moments[hypothesis.momentIndex]
        let noteMask = Self.pitchMask(for: pitch)
        let expected = moment.pitchMask(for: hypothesis.mode)
        let isExpected = expected & noteMask != 0
        let isSupplementalHand = moment.allPitchMask & noteMask != 0 && !isExpected
        let wasAlreadyPerformed = hypothesis.performedPitchMask & noteMask != 0

        if isExpected && !wasAlreadyPerformed {
            continued.performedPitchMask |= noteMask
            continued.score += exactPitchReward(expectedPitchMask: expected)
                * velocityWeight(for: velocity)
            continued.evidenceEventCount += 1
            continued.mismatchLoad *= 0.55
            updateIntraGestureTiming(of: &continued, timestamp: timestamp)
        } else if isSupplementalHand && !wasAlreadyPerformed {
            continued.performedPitchMask |= noteMask
            continued.score += Configuration.supplementalHandReward
            continued.mismatchLoad *= 0.8
            updateIntraGestureTiming(of: &continued, timestamp: timestamp)
        } else {
            let wasReleased = hypothesis.releasedPitchMask & noteMask != 0
            continued.score -= wasAlreadyPerformed && !wasReleased
                ? Configuration.repeatedWithoutReleasePenalty
                : Configuration.wrongPitchPenalty
            continued.mismatchLoad += 1
        }

        if Self.valid(timestamp) {
            continued.lastNoteOnAt = timestamp
        }
        return continued
    }

    private func transitioning(
        _ hypothesis: Hypothesis,
        to target: Int,
        with pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        in compiled: CompiledReference
    ) -> Hypothesis {
        var transitioned = hypothesis
        let currentMoment = compiled.moments[hypothesis.momentIndex]
        let targetMoment = compiled.moments[target]
        let currentExpected = currentMoment.pitchMask(for: hypothesis.mode)
        let targetExpected = targetMoment.pitchMask(for: hypothesis.mode)
        let noteMask = Self.pitchMask(for: pitch)
        let currentMatched = hypothesis.performedPitchMask & currentExpected
        let currentCoverage = Self.coverage(matched: currentMatched, expected: currentExpected)
        let direction = target > hypothesis.momentIndex ? 1 : -1

        transitioned.score += finalizationScore(
            performed: hypothesis.performedPitchMask,
            expected: currentExpected,
            fullExpected: currentMoment.allPitchMask
        )
        transitioned.score += boundaryScore(
            hypothesis,
            currentCoverage: currentCoverage,
            target: target,
            pitchMask: noteMask,
            timestamp: timestamp,
            in: compiled
        )
        transitioned.score -= transitionDistancePenalty(
            from: hypothesis.momentIndex,
            to: target,
            mode: hypothesis.mode,
            in: compiled
        )

        let isExpected = targetExpected & noteMask != 0
        let isSupplemental = targetMoment.allPitchMask & noteMask != 0 && !isExpected
        if isExpected {
            transitioned.score += exactPitchReward(expectedPitchMask: targetExpected)
                * velocityWeight(for: velocity)
            transitioned.mismatchLoad *= 0.5
            transitioned.evidenceEventCount += 1
        } else if isSupplemental {
            transitioned.score += Configuration.supplementalHandReward
            transitioned.mismatchLoad *= 0.85
        } else {
            transitioned.score -= Configuration.substitutionPenalty
            transitioned.mismatchLoad += 0.8
        }

        if hypothesis.kind != .primary {
            let distinguishing = currentMoment.distinctiveness[Int(hypothesis.mode.rawValue)]
            if currentCoverage >= 0.7 {
                transitioned.probeEvidence += distinguishing * currentCoverage
            } else {
                transitioned.probeEvidence *= 0.8
            }
        }

        applyTransitionTiming(
            to: &transitioned,
            target: target,
            timestamp: timestamp,
            direction: direction,
            in: compiled
        )
        transitioned.lastCompletedGestureMask = hypothesis.performedPitchMask
        transitioned.momentIndex = target
        transitioned.performedPitchMask = noteMask
        transitioned.releasedPitchMask = 0
        transitioned.gestureStartedAt = Self.valid(timestamp) ? timestamp : nil
        transitioned.lastNoteOnAt = Self.valid(timestamp) ? timestamp : nil
        transitioned.gestureCount += 1
        return transitioned
    }

    private func forwardTargets(
        from hypothesis: Hypothesis,
        matching pitch: UInt8,
        in compiled: CompiledReference
    ) -> [Int] {
        let noteMask = Self.pitchMask(for: pitch)
        let current = hypothesis.momentIndex
        let currentMoment = compiled.moments[current]
        let currentExpected = currentMoment.pitchMask(for: hypothesis.mode)
        let unmatchedCurrent = currentExpected & ~hypothesis.performedPitchMask
        let isSupplementalCurrentPitch = hypothesis.mode != .both
            && currentMoment.allPitchMask & noteMask != 0
            && currentExpected & noteMask == 0
        let currentCoverage = Self.coverage(
            matched: hypothesis.performedPitchMask & currentExpected,
            expected: currentExpected
        )
        let hasReleaseEvidence = hypothesis.releasedPitchMask != 0

        // A pitch belonging only to the other notated hand is useful participation evidence,
        // but must never advance a one-hand hypothesis—even if the same pitch appears soon in
        // the followed hand.
        if isSupplementalCurrentPitch {
            return []
        }

        var targets: [Int] = []
        targets.reserveCapacity(Configuration.maximumForwardTargets + 1)

        var forwardRelevantCount = 0
        var index = current + 1
        while index < compiled.moments.count,
              forwardRelevantCount < Configuration.maximumForwardTargets {
            let moment = compiled.moments[index]
            let expected = moment.pitchMask(for: hypothesis.mode)
            if expected != 0 {
                forwardRelevantCount += 1
                let measureDistance = moment.measureOffset - currentMoment.measureOffset
                if measureDistance > 1 { break }
                if expected & noteMask != 0 {
                    let shouldPreferCurrent = unmatchedCurrent & noteMask != 0
                        && currentCoverage < 0.8
                        && !hasReleaseEvidence
                    if !shouldPreferCurrent {
                        targets.append(index)
                    }
                }
            }
            index += 1
        }

        // Always retain the immediately following active moment as a substitution path.
        if let immediate = nextRelevantMoment(
            after: current,
            mode: hypothesis.mode,
            in: compiled
        ), !targets.contains(immediate) {
            let immediateMeasure = compiled.moments[immediate].measureOffset
            let isReachable: Bool
            if hypothesis.kind != .primary {
                isReachable = true
            } else {
                let bounds = localMeasureBounds(
                    around: currentMoment.measureOffset,
                    in: compiled
                )
                isReachable = immediateMeasure <= currentMoment.measureOffset + 1
                    && bounds.contains(immediateMeasure)
            }
            if isReachable {
                targets.append(immediate)
            }
        }

        return targets
    }

    private func nextRelevantMoment(
        after index: Int,
        mode: ParticipationMode,
        in compiled: CompiledReference
    ) -> Int? {
        var candidate = index + 1
        while candidate < compiled.moments.count {
            if compiled.moments[candidate].pitchMask(for: mode) != 0 {
                return candidate
            }
            candidate += 1
        }
        return nil
    }

    private func localMeasureBounds(
        around measureOffset: Int,
        in compiled: CompiledReference
    ) -> ClosedRange<Int> {
        var lower = max(0, measureOffset - 1)
        var upper = min(compiled.measures.count - 1, measureOffset + 1)
        if let acquisitionMeasureOffsets, phase == .acquiring {
            lower = min(lower, acquisitionMeasureOffsets.lowerBound)
            upper = max(upper, acquisitionMeasureOffsets.upperBound)
        }
        return lower...upper
    }

    // MARK: - Evidence scoring

    private func exactPitchReward(expectedPitchMask: UInt128) -> Double {
        Configuration.fullGestureReward
            / Double(max(1, expectedPitchMask.nonzeroBitCount))
    }

    private func velocityWeight(for velocity: UInt8) -> Double {
        0.65 + 0.35 * Double(min(velocity, 127)) / 127
    }

    private func finalizationScore(
        performed: UInt128,
        expected: UInt128,
        fullExpected: UInt128
    ) -> Double {
        guard expected != 0 else { return 0 }
        let matched = performed & expected
        let missingRatio = 1 - Self.coverage(matched: matched, expected: expected)
        let actualWrong = performed & ~fullExpected
        let wrongRatio = Double(actualWrong.nonzeroBitCount)
            / Double(max(1, performed.nonzeroBitCount))
        return -Configuration.missingGesturePenalty * missingRatio
            - Configuration.wrongPitchPenalty * wrongRatio
    }

    private func boundaryScore(
        _ hypothesis: Hypothesis,
        currentCoverage: Double,
        target: Int,
        pitchMask: UInt128,
        timestamp: MIDITimeStamp,
        in compiled: CompiledReference
    ) -> Double {
        let current = compiled.moments[hypothesis.momentIndex]
        let currentExpected = current.pitchMask(for: hypothesis.mode)
        let alreadyPerformed = hypothesis.performedPitchMask & pitchMask != 0
        let wasReleased = hypothesis.releasedPitchMask & pitchMask != 0
        let unmatchedExpectedPitch = currentExpected & pitchMask != 0 && !alreadyPerformed

        var score = 0.0
        if alreadyPerformed {
            score += wasReleased ? 1.65 : -Configuration.repeatedWithoutReleasePenalty
        }
        if currentCoverage >= 0.999 {
            score += 0.75
        } else {
            score -= Configuration.incompleteBoundaryPenalty * (1 - currentCoverage)
        }
        let releasedCoverage = Self.coverage(
            matched: hypothesis.releasedPitchMask & currentExpected,
            expected: currentExpected
        )
        let writtenDuration = current.averageDuration[Int(hypothesis.mode.rawValue)]
        if releasedCoverage > 0 {
            // Release is useful boundary evidence, especially for shorter written gestures.
            let pedalWeight = sustainIsDown || sostenutoIsDown ? 0.35 : 1
            score += releasedCoverage
                * min(0.75, 0.35 + 0.2 / max(0.25, writtenDuration))
                * pedalWeight
        }
        if unmatchedExpectedPitch {
            score -= current.attack == .rolled ? 3.0 : 2.25
        }
        if current.attack == .rolled && currentCoverage < 0.8 {
            score -= 0.6
        }

        if let gap = Self.elapsedTicks(from: hypothesis.lastNoteOnAt, to: timestamp),
           let intra = hypothesis.intraGestureTicks,
           intra > 0 {
            let logRatio = Foundation.log(max(gap, 1) / intra)
            score += min(1.25, max(-0.5, logRatio * 0.35))
        }

        return score
    }

    private func transitionDistancePenalty(
        from source: Int,
        to target: Int,
        mode: ParticipationMode,
        in compiled: CompiledReference
    ) -> Double {
        let direction = target > source ? 1 : -1
        let range = direction > 0 ? (source + 1)..<target : (target + 1)..<source
        var skippedActiveMoments = 0
        if !range.isEmpty {
            for index in range where compiled.moments[index].pitchMask(for: mode) != 0 {
                skippedActiveMoments += 1
            }
        }
        let sourceMeasure = compiled.moments[source].measureOffset
        let targetMeasure = compiled.moments[target].measureOffset
        let measureDistance = abs(targetMeasure - sourceMeasure)
        let measurePenalty = measureDistance > 1
            ? Double(measureDistance - 1) * Configuration.adjacentMeasurePenalty
            : 0
        return Double(skippedActiveMoments) * Configuration.skippedMomentPenalty
            + measurePenalty
    }

    private func updateIntraGestureTiming(
        of hypothesis: inout Hypothesis,
        timestamp: MIDITimeStamp
    ) {
        guard let elapsed = Self.elapsedTicks(from: hypothesis.lastNoteOnAt, to: timestamp) else {
            return
        }
        hypothesis.intraGestureTicks = Self.smoothed(
            hypothesis.intraGestureTicks,
            with: elapsed,
            factor: 0.2
        )
    }

    private func applyTransitionTiming(
        to hypothesis: inout Hypothesis,
        target: Int,
        timestamp: MIDITimeStamp,
        direction: Int,
        in compiled: CompiledReference
    ) {
        guard let elapsed = Self.elapsedTicks(from: hypothesis.gestureStartedAt, to: timestamp) else {
            return
        }

        guard direction > 0 else {
            hypothesis.ticksPerBeat = nil
            return
        }
        let beatDistance = compiled.moments[target].beat
            - compiled.moments[hypothesis.momentIndex].beat
        guard beatDistance > 0 else { return }
        let observed = elapsed / beatDistance
        guard observed > 0 else { return }

        if let estimated = hypothesis.ticksPerBeat, estimated > 0 {
            let ratio = observed / estimated
            if ratio < 4 {
                let deviation = max(0, abs(Foundation.log(ratio)) - Foundation.log(2.0))
                hypothesis.score -= deviation * 0.55
                hypothesis.ticksPerBeat = Self.smoothed(estimated, with: observed, factor: 0.18)
            }
        } else {
            hypothesis.ticksPerBeat = observed
        }
    }

    private static func smoothed(_ previous: Double?, with sample: Double, factor: Double) -> Double {
        guard let previous else { return sample }
        return previous * (1 - factor) + sample * factor
    }

    // MARK: - Beam pruning

    private func prune(
        _ candidates: [Hypothesis],
        limit: Int,
        in compiled: CompiledReference
    ) -> [Hypothesis] {
        var bestByState: [HypothesisState: Hypothesis] = [:]
        bestByState.reserveCapacity(candidates.count)
        for candidate in candidates where candidate.score.isFinite {
            let state = HypothesisState(
                momentIndex: candidate.momentIndex,
                mode: candidate.mode,
                kind: candidate.kind,
                performedPitchMask: candidate.performedPitchMask,
                releasedPitchMask: candidate.releasedPitchMask,
                gestureCount: candidate.gestureCount
            )
            if bestByState[state]?.score ?? -.infinity < candidate.score {
                bestByState[state] = candidate
            }
        }

        var ranked = Array(bestByState.values)
        ranked.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.momentIndex != $1.momentIndex {
                return $0.momentIndex < $1.momentIndex
            }
            if $0.mode != $1.mode { return $0.mode.rawValue < $1.mode.rawValue }
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            if $0.gestureCount != $1.gestureCount {
                return $0.gestureCount < $1.gestureCount
            }
            if $0.performedPitchMask != $1.performedPitchMask {
                return $0.performedPitchMask < $1.performedPitchMask
            }
            return $0.releasedPitchMask < $1.releasedPitchMask
        }
        guard ranked.count > limit else { return ranked }

        var selected: [Hypothesis] = []
        selected.reserveCapacity(limit)
        var selectedStates = Set<HypothesisState>()

        // Retain the best interpretation of every hand mode.
        for mode in ParticipationMode.allCases {
            guard let candidate = ranked.first(where: { $0.mode == mode }) else { continue }
            appendIfNew(candidate, to: &selected, states: &selectedStates)
        }

        // Retain geographic diversity by engraving measure before filling by raw score.
        var bestByMeasure: [Int: Hypothesis] = [:]
        for candidate in ranked {
            let measure = compiled.moments[candidate.momentIndex].measureOffset
            if bestByMeasure[measure]?.score ?? -.infinity < candidate.score {
                bestByMeasure[measure] = candidate
            }
        }
        for candidate in bestByMeasure.values.sorted(by: {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.momentIndex != $1.momentIndex {
                return $0.momentIndex < $1.momentIndex
            }
            return $0.mode.rawValue < $1.mode.rawValue
        }) {
            guard selected.count < min(limit, max(6, limit / 2)) else { break }
            appendIfNew(candidate, to: &selected, states: &selectedStates)
        }

        for candidate in ranked {
            guard selected.count < limit else { break }
            appendIfNew(candidate, to: &selected, states: &selectedStates)
        }
        return selected
    }

    private func appendIfNew(
        _ candidate: Hypothesis,
        to selected: inout [Hypothesis],
        states: inout Set<HypothesisState>
    ) {
        let state = HypothesisState(
            momentIndex: candidate.momentIndex,
            mode: candidate.mode,
            kind: candidate.kind,
            performedPitchMask: candidate.performedPitchMask,
            releasedPitchMask: candidate.releasedPitchMask,
            gestureCount: candidate.gestureCount
        )
        if states.insert(state).inserted {
            selected.append(candidate)
        }
    }

    // MARK: - Visible replay

    /// Maintains an earlier, forward-running interpretation without allowing it to influence
    /// the published position. A replay is a change of origin, not a backward transition.
    private func updateReplay(
        with pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        previousPrimaryBest: Hypothesis,
        primaryBest: Hypothesis,
        in compiled: CompiledReference
    ) {
        guard let committedMomentIndex,
              let visibleRange = Self.validRange(visibleRange) else {
            clearReplayProbe()
            return
        }
        let shouldSeed = canBeginNewGesture(
            from: previousPrimaryBest,
            with: pitch,
            in: compiled
        )
        guard !replayHypotheses.isEmpty || shouldSeed else { return }

        var candidates: [Hypothesis] = []
        candidates.reserveCapacity(
            replayHypotheses.count * (2 + Configuration.maximumForwardTargets)
                + Configuration.maximumReplaySeedsPerMode * ParticipationMode.allCases.count
        )

        for hypothesis in replayHypotheses {
            expand(
                hypothesis,
                with: pitch,
                velocity: velocity,
                timestamp: timestamp,
                in: compiled,
                into: &candidates
            )
        }

        if shouldSeed {
            candidates.append(contentsOf: replaySeeds(
                for: pitch,
                velocity: velocity,
                timestamp: timestamp,
                scoreBase: primaryBest.score,
                before: committedMomentIndex,
                visibleRange: visibleRange,
                in: compiled
            ))
        }

        candidates.removeAll { candidate in
            candidate.seedMomentIndex >= committedMomentIndex
                || candidate.momentIndex >= committedMomentIndex
                || !isMomentVisible(candidate.momentIndex, in: visibleRange, compiled: compiled)
        }
        replayHypotheses = prune(
            candidates,
            limit: Configuration.replayBeamWidth,
            in: compiled
        )
    }

    private func replaySeeds(
        for pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        scoreBase: Double,
        before committedMomentIndex: Int,
        visibleRange: ClosedRange<Double>,
        in compiled: CompiledReference
    ) -> [Hypothesis] {
        var ranked: [ProbeSeed] = []
        ranked.reserveCapacity(
            Configuration.maximumReplaySeedsPerMode * ParticipationMode.allCases.count
        )

        for mode in ParticipationMode.allCases {
            let occurrences = compiled.momentsByPitch[Int(mode.rawValue)][Int(pitch)]
            var modeSeeds: [ProbeSeed] = []
            modeSeeds.reserveCapacity(min(occurrences.count, 24))
            for momentIndex in occurrences where momentIndex < committedMomentIndex {
                guard isMomentVisible(momentIndex, in: visibleRange, compiled: compiled) else {
                    continue
                }
                let historySimilarity = historicalSimilarity(
                    endingBefore: momentIndex,
                    mode: mode,
                    in: compiled
                )
                let distinctiveness = compiled.moments[momentIndex]
                    .distinctiveness[Int(mode.rawValue)]
                modeSeeds.append(ProbeSeed(
                    momentIndex: momentIndex,
                    mode: mode,
                    evidence: historySimilarity * 2.4 + distinctiveness
                ))
            }
            modeSeeds.sort {
                if $0.evidence != $1.evidence { return $0.evidence > $1.evidence }
                return $0.momentIndex > $1.momentIndex
            }
            ranked.append(contentsOf: modeSeeds.prefix(Configuration.maximumReplaySeedsPerMode))
        }

        let velocityWeight = self.velocityWeight(for: velocity)
        let seeded = ranked.map { seed in
            let expected = compiled.moments[seed.momentIndex].pitchMask(for: seed.mode)
            return Hypothesis(
                momentIndex: seed.momentIndex,
                mode: seed.mode,
                kind: .replay,
                performedPitchMask: Self.pitchMask(for: pitch),
                releasedPitchMask: 0,
                score: scoreBase
                    - Configuration.replaySeedPenalty
                    + seed.evidence
                    + exactPitchReward(expectedPitchMask: expected) * velocityWeight,
                gestureStartedAt: Self.valid(timestamp) ? timestamp : nil,
                lastNoteOnAt: Self.valid(timestamp) ? timestamp : nil,
                ticksPerBeat: nil,
                intraGestureTicks: nil,
                gestureCount: 0,
                evidenceEventCount: 1,
                mismatchLoad: 0,
                probeEvidence: compiled.moments[seed.momentIndex]
                    .distinctiveness[Int(seed.mode.rawValue)] * 0.25,
                seedMomentIndex: seed.momentIndex,
                lastCompletedGestureMask: 0
            )
        }
        return prune(seeded, limit: Configuration.replayBeamWidth, in: compiled)
    }

    private func canBeginNewGesture(
        from hypothesis: Hypothesis,
        with pitch: UInt8,
        in compiled: CompiledReference
    ) -> Bool {
        let moment = compiled.moments[hypothesis.momentIndex]
        let expected = moment.pitchMask(for: hypothesis.mode)
        let pitchMask = Self.pitchMask(for: pitch)
        let alreadyPerformed = hypothesis.performedPitchMask & pitchMask != 0
        let unmatchedExpected = expected & pitchMask != 0 && !alreadyPerformed
        guard !unmatchedExpected else { return false }

        let coverage = Self.coverage(
            matched: hypothesis.performedPitchMask & expected,
            expected: expected
        )
        if moment.attack == .rolled && coverage < 0.8 {
            return false
        }
        if alreadyPerformed {
            return hypothesis.releasedPitchMask & pitchMask != 0
        }
        return coverage >= 0.7
    }

    private func commitReplayIfReady(
        primaryBest: Hypothesis,
        in compiled: CompiledReference
    ) -> Bool {
        guard phase != .acquiring,
              let committedMomentIndex,
              let visibleRange = Self.validRange(visibleRange),
              let replayBest = replayHypotheses.max(by: { $0.score < $1.score }),
              replayBest.seedMomentIndex < committedMomentIndex,
              replayBest.momentIndex < committedMomentIndex,
              replayBest.gestureCount >= 2,
              replayBest.probeEvidence >= Configuration.replayEvidenceRequired,
              replayBest.score >= primaryBest.score + Configuration.replayCommitLead,
              isMomentVisible(replayBest.momentIndex, in: visibleRange, compiled: compiled) else {
            return false
        }

        primaryHypotheses = replayHypotheses.map { hypothesis in
            var promoted = hypothesis
            promoted.kind = .primary
            promoted.mismatchLoad = 0
            promoted.probeEvidence = 0
            return promoted
        }
        self.committedMomentIndex = replayBest.momentIndex
        phase = .tracking
        poorEvidenceStreak = 0
        clearReplayProbe()
        clearRelocationProbe()
        recentObservedGestures.removeAll(keepingCapacity: true)
        lastCommittedGestureCount = replayBest.gestureCount
        return true
    }

    private func clearReplayProbe() {
        replayHypotheses.removeAll(keepingCapacity: true)
    }

    private func isMomentVisible(
        _ momentIndex: Int,
        in visibleRange: ClosedRange<Double>,
        compiled: CompiledReference
    ) -> Bool {
        let moment = compiled.moments[momentIndex]
        let epsilon = EngravingReference.simultaneousBeatEpsilon
        let lineRange = compiled.lines[moment.lineOffset].beatRange
        if visibleRange.upperBound - visibleRange.lowerBound <= epsilon {
            let sample = visibleRange.lowerBound
            return abs(moment.beat - sample) <= epsilon
                && sample >= lineRange.lowerBound - epsilon
                && sample <= lineRange.upperBound + epsilon
        }
        return moment.beat >= visibleRange.lowerBound - epsilon
            && moment.beat <= visibleRange.upperBound + epsilon
            && Self.hasPositiveOverlap(lineRange, visibleRange)
    }

    // MARK: - Global relocation

    private func clearRelocationProbe() {
        relocationHypotheses.removeAll(keepingCapacity: true)
        relocationWinningStreak = 0
        lastRelocationWinningGestureCount = 0
    }

    private func updateRelocationProbe(
        with pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        primaryBest: Hypothesis,
        in compiled: CompiledReference
    ) {
        if relocationHypotheses.isEmpty {
            relocationHypotheses = relocationSeeds(
                for: pitch,
                velocity: velocity,
                timestamp: timestamp,
                primaryBest: primaryBest,
                in: compiled
            )
            return
        }

        var expanded: [Hypothesis] = []
        expanded.reserveCapacity(
            relocationHypotheses.count * (2 + Configuration.maximumForwardTargets)
        )
        for hypothesis in relocationHypotheses {
            expand(
                hypothesis,
                with: pitch,
                velocity: velocity,
                timestamp: timestamp,
                in: compiled,
                into: &expanded
            )
        }
        relocationHypotheses = prune(
            expanded,
            limit: Configuration.relocationBeamWidth,
            in: compiled
        )
    }

    private struct ProbeSeed {
        let momentIndex: Int
        let mode: ParticipationMode
        let evidence: Double
    }

    private func relocationSeeds(
        for pitch: UInt8,
        velocity: UInt8,
        timestamp: MIDITimeStamp,
        primaryBest: Hypothesis,
        in compiled: CompiledReference
    ) -> [Hypothesis] {
        var ranked: [ProbeSeed] = []
        ranked.reserveCapacity(
            Configuration.maximumRelocationSeedsPerMode * ParticipationMode.allCases.count * 2
        )
        let currentVisibleRange = Self.validRange(visibleRange)
        let primaryMeasureOffset = compiled.moments[primaryBest.momentIndex].measureOffset

        for mode in ParticipationMode.allCases {
            let occurrences = compiled.momentsByPitch[Int(mode.rawValue)][Int(pitch)]
            var modeSeeds: [ProbeSeed] = []
            modeSeeds.reserveCapacity(occurrences.count)
            for momentIndex in occurrences {
                let measureOffset = compiled.moments[momentIndex].measureOffset
                if momentIndex >= primaryBest.momentIndex,
                   measureOffset <= primaryMeasureOffset + 1 {
                    // The primary lane owns continuous forward motion through the following
                    // measure. Earlier offscreen moments remain valid jump destinations even
                    // when they are musically adjacent to the current position.
                    continue
                }
                if let currentVisibleRange,
                   isMomentVisible(momentIndex, in: currentVisibleRange, compiled: compiled) {
                    continue
                }
                let historySimilarity = historicalSimilarity(
                    endingBefore: momentIndex,
                    mode: mode,
                    in: compiled
                )
                let distinctiveness = compiled.moments[momentIndex]
                    .distinctiveness[Int(mode.rawValue)]
                modeSeeds.append(ProbeSeed(
                    momentIndex: momentIndex,
                    mode: mode,
                    evidence: historySimilarity * 2.4 + distinctiveness
                ))
            }
            modeSeeds.sort {
                $0.evidence == $1.evidence
                    ? $0.momentIndex < $1.momentIndex
                    : $0.evidence > $1.evidence
            }
            ranked.append(contentsOf: modeSeeds.prefix(Configuration.maximumRelocationSeedsPerMode))
        }

        let velocityWeight = self.velocityWeight(for: velocity)
        let seeded = ranked.map { seed in
            let expected = compiled.moments[seed.momentIndex].pitchMask(for: seed.mode)
            return Hypothesis(
                momentIndex: seed.momentIndex,
                mode: seed.mode,
                kind: .relocation,
                performedPitchMask: Self.pitchMask(for: pitch),
                releasedPitchMask: 0,
                score: primaryBest.score
                    - Configuration.relocationSeedPenalty
                    + seed.evidence
                    + exactPitchReward(expectedPitchMask: expected) * velocityWeight,
                gestureStartedAt: Self.valid(timestamp) ? timestamp : nil,
                lastNoteOnAt: Self.valid(timestamp) ? timestamp : nil,
                ticksPerBeat: nil,
                intraGestureTicks: nil,
                gestureCount: 0,
                evidenceEventCount: 1,
                mismatchLoad: 0,
                probeEvidence: compiled.moments[seed.momentIndex]
                    .distinctiveness[Int(seed.mode.rawValue)] * 0.25,
                seedMomentIndex: seed.momentIndex,
                lastCompletedGestureMask: 0
            )
        }
        return prune(seeded, limit: Configuration.relocationBeamWidth, in: compiled)
    }

    private func historicalSimilarity(
        endingBefore momentIndex: Int,
        mode: ParticipationMode,
        in compiled: CompiledReference
    ) -> Double {
        guard !recentObservedGestures.isEmpty else { return 0 }
        var referenceIndex = momentIndex
        var total = 0.0
        var count = 0
        for observed in recentObservedGestures.reversed() {
            referenceIndex -= 1
            while referenceIndex >= 0,
                  compiled.moments[referenceIndex].pitchMask(for: mode) == 0 {
                referenceIndex -= 1
            }
            guard referenceIndex >= 0 else { break }
            let expected = compiled.moments[referenceIndex].pitchMask(for: mode)
            total += Self.pitchSetSimilarity(observed, expected)
            count += 1
        }
        return count == 0 ? 0 : total / Double(count)
    }

    private func commitRelocationIfReady(
        primaryBest: Hypothesis,
        in compiled: CompiledReference
    ) -> Bool {
        guard phase == .lost,
              let relocationBest = relocationHypotheses.max(by: { $0.score < $1.score }),
              relocationBest.probeEvidence >= Configuration.relocationEvidenceRequired,
              relocationBest.score >= primaryBest.score + Configuration.relocationCommitLead else {
            relocationWinningStreak = 0
            lastRelocationWinningGestureCount = 0
            return false
        }

        if relocationBest.gestureCount > lastRelocationWinningGestureCount {
            relocationWinningStreak += 1
            lastRelocationWinningGestureCount = relocationBest.gestureCount
        }
        guard relocationWinningStreak >= 2 else { return false }

        primaryHypotheses = relocationHypotheses.map { hypothesis in
            var promoted = hypothesis
            promoted.kind = .primary
            promoted.mismatchLoad = 0
            promoted.probeEvidence = 0
            return promoted
        }
        clearRelocationProbe()
        poorEvidenceStreak = 0
        phase = .tracking
        committedMomentIndex = relocationBest.momentIndex
        clearReplayProbe()
        retainLocalHypotheses(around: relocationBest.momentIndex, in: compiled)
        lastCommittedGestureCount = relocationBest.gestureCount
        recentObservedGestures.removeAll(keepingCapacity: true)
        return true
    }

    // MARK: - Commitment and public result

    private func makeUpdate(
        from bestCandidate: Hypothesis,
        observedPitch: UInt8,
        didReplay: Bool,
        didRelocate: Bool,
        in compiled: CompiledReference
    ) -> Update {
        let localCandidates = primaryHypotheses.isEmpty ? [bestCandidate] : primaryHypotheses
        let positionScores = groupedPositionScores(from: localCandidates)
        let bestPosition = positionScores.first
            ?? PositionScore(momentIndex: bestCandidate.momentIndex, score: bestCandidate.score)
        let best = bestHypothesis(
            at: bestPosition.momentIndex,
            among: localCandidates
        )
            ?? bestCandidate

        let confidence = confidence(
            for: best,
            positionScores: positionScores,
            in: compiled
        )
        updateParticipation(
            observedPitch: observedPitch,
            at: best.momentIndex,
            in: compiled
        )

        var completedAcquisition = false
        if phase == .acquiring {
            let expected = compiled.moments[best.momentIndex].pitchMask(for: best.mode)
            let coverage = Self.coverage(
                matched: best.performedPitchMask & expected,
                expected: expected
            )
            let hasEnoughEvidence = best.evidenceEventCount >= Configuration.acquisitionEvidenceToTrack
                || (expected.nonzeroBitCount > 1 && coverage >= 0.999)
            if hasEnoughEvidence && (confidence >= 0.52 || acquisitionMeasureOffsets != nil) {
                phase = .tracking
                committedMomentIndex = best.momentIndex
                retainLocalHypotheses(around: best.momentIndex, in: compiled)
                completedAcquisition = true
            }
        } else if phase == .lost,
                  best.mismatchLoad < Configuration.poorEvidenceToRelocate * 0.45 {
            phase = .tracking
            poorEvidenceStreak = 0
            clearRelocationProbe()
        }

        let holdsPresentation = hasCredibleProbe(relativeTo: best)
        let hasDirectPositionEvidence = directlySupportsPosition(best, in: compiled)
        var trackingState: TrackingState
        switch phase {
        case .awaitingPerformance, .acquiring: trackingState = .acquiring
        case .tracking:
            trackingState = confidence >= 0.45
                && hasDirectPositionEvidence
                && !holdsPresentation
                ? .tracking
                : .uncertain
        case .lost: trackingState = .lost
        }

        if didRelocate || didReplay {
            committedMomentIndex = best.momentIndex
        } else if trackingState == .tracking {
            let floor = committedMomentIndex ?? best.momentIndex
            committedMomentIndex = max(floor, best.momentIndex)
        }

        let publishedMomentIndex = committedMomentIndex ?? best.momentIndex
        let publishedBest = bestHypothesis(
            at: publishedMomentIndex,
            among: localCandidates
        )
            ?? best

        if trackingState == .tracking {
            updateObservedGestureHistory(using: publishedBest)
        }

        var effectiveDidRelocate = didRelocate
        if displayMomentIndex == nil {
            displayMomentIndex = publishedMomentIndex
        } else if didRelocate {
            displayMomentIndex = publishedMomentIndex
        } else if completedAcquisition,
                  let currentDisplayIndex = displayMomentIndex,
                  publishedMomentIndex < currentDisplayIndex {
            // Acquisition may revise an early, provisional marker. Present that correction as
            // one explicit jump rather than an unexplained backward movement.
            displayMomentIndex = publishedMomentIndex
            effectiveDidRelocate = true
        } else if trackingState == .tracking,
                  !didReplay,
                  let currentDisplayIndex = displayMomentIndex {
            displayMomentIndex = max(currentDisplayIndex, publishedMomentIndex)
        }

        let resolvedDisplayIndex = displayMomentIndex ?? publishedMomentIndex
        if let viewportLineOffset,
           !effectiveDidRelocate {
            let displayLineOffset = compiled.moments[resolvedDisplayIndex].lineOffset
            if displayLineOffset > viewportLineOffset + 1 {
                // Skipping over an engraving line is a discontinuity from the performer's
                // perspective even when the musical hypothesis moved in the forward direction.
                effectiveDidRelocate = true
            }
        } else if viewportLineOffset == nil,
                  trackingState == .tracking,
                  let visibleRange = Self.validRange(visibleRange),
                  !isMomentVisible(
                    resolvedDisplayIndex,
                    in: visibleRange,
                    compiled: compiled
                  ) {
            effectiveDidRelocate = true
        }

        if effectiveDidRelocate {
            displayMomentIndex = publishedMomentIndex
            trackingState = .tracking
        }

        let plausibleRange = plausibleBeatRange(
            around: publishedBest,
            positionScores: positionScores,
            in: compiled
        )
        let viewport = viewportRecommendation(
            displayMomentIndex: displayMomentIndex ?? publishedMomentIndex,
            state: trackingState,
            didReplay: didReplay,
            didRelocate: effectiveDidRelocate,
            in: compiled
        )
        let moment = compiled.moments[publishedMomentIndex]
        let displayMoment = compiled.moments[displayMomentIndex ?? publishedMomentIndex]
        let update = Update(
            beat: moment.beat,
            displayBeat: displayMoment.beat,
            plausibleBeatRange: plausibleRange,
            measureIndex: compiled.measures[moment.measureOffset].index,
            confidence: confidence,
            state: trackingState,
            activeHands: inferredParticipation,
            viewport: viewport,
            didRelocate: effectiveDidRelocate
        )
        assertPresentationInvariants(previous: lastUpdate, current: update, in: compiled)
        lastUpdate = update
        return update
    }

    private func hasCredibleProbe(relativeTo primaryBest: Hypothesis) -> Bool {
        if let replayBest = replayHypotheses.max(by: { $0.score < $1.score }),
           replayBest.gestureCount > 0,
           replayBest.score >= primaryBest.score - Configuration.replayCommitLead {
            return true
        }
        if let relocationBest = relocationHypotheses.max(by: { $0.score < $1.score }),
           relocationBest.gestureCount > 0,
           relocationBest.score >= primaryBest.score - Configuration.relocationCommitLead {
            return true
        }
        return false
    }

    private func directlySupportsPosition(
        _ hypothesis: Hypothesis,
        in compiled: CompiledReference
    ) -> Bool {
        let expected = compiled.moments[hypothesis.momentIndex].pitchMask(for: hypothesis.mode)
        return hypothesis.performedPitchMask & expected != 0
    }

    /// Discards score-wide acquisition alternatives after a local commitment. From this point,
    /// distant candidates may only re-enter through the guarded relocation beam.
    private func retainLocalHypotheses(
        around momentIndex: Int,
        in compiled: CompiledReference
    ) {
        let measureOffset = compiled.moments[momentIndex].measureOffset
        let bounds = localMeasureBounds(around: measureOffset, in: compiled)
        primaryHypotheses.removeAll {
            !bounds.contains(compiled.moments[$0.momentIndex].measureOffset)
        }
    }

    private func groupedPositionScores(from candidates: [Hypothesis]) -> [PositionScore] {
        var bestByPosition: [PositionKey: Double] = [:]
        bestByPosition.reserveCapacity(candidates.count)
        for candidate in candidates {
            let key = PositionKey(momentIndex: candidate.momentIndex)
            if bestByPosition[key] ?? -.infinity < candidate.score {
                bestByPosition[key] = candidate.score
            }
        }
        return bestByPosition.map { key, score in
            PositionScore(momentIndex: key.momentIndex, score: score)
        }.sorted {
            $0.score == $1.score
                ? $0.momentIndex < $1.momentIndex
                : $0.score > $1.score
        }
    }

    private func bestHypothesis(
        at momentIndex: Int,
        among candidates: [Hypothesis]
    ) -> Hypothesis? {
        var result: Hypothesis?
        for candidate in candidates where candidate.momentIndex == momentIndex {
            if result?.score ?? -.infinity < candidate.score {
                result = candidate
            }
        }
        return result
    }

    private func confidence(
        for best: Hypothesis,
        positionScores: [PositionScore],
        in compiled: CompiledReference
    ) -> Double {
        let alternativeScore = positionScores.dropFirst().first?.score
        let marginComponent: Double
        if let alternativeScore {
            let gap = best.score - alternativeScore
            marginComponent = 1 / (1 + Foundation.exp(-gap / Configuration.confidenceScale))
        } else {
            marginComponent = 0.82
        }

        let evidenceComponent = 1 - Foundation.exp(-Double(best.evidenceEventCount) / 2.5)
        let expected = compiled.moments[best.momentIndex].pitchMask(for: best.mode)
        let coverage = Self.coverage(
            matched: best.performedPitchMask & expected,
            expected: expected
        )
        let mismatchComponent = Foundation.exp(-best.mismatchLoad * 0.28)
        return min(
            1,
            max(
                0,
                marginComponent * 0.55
                    + evidenceComponent * 0.2
                    + coverage * 0.15
                    + mismatchComponent * 0.1
            )
        )
    }

    private func plausibleBeatRange(
        around best: Hypothesis,
        positionScores: [PositionScore],
        in compiled: CompiledReference
    ) -> ClosedRange<Double> {
        let bestScore = positionScores.first?.score ?? best.score
        let bestMeasure = compiled.moments[best.momentIndex].measureOffset
        var beats: [Double] = [compiled.moments[best.momentIndex].beat]
        for position in positionScores.dropFirst() {
            guard position.score >= bestScore - Configuration.plausibleScoreWindow else { break }
            let moment = compiled.moments[position.momentIndex]
            guard abs(moment.measureOffset - bestMeasure) <= 1 else { continue }
            beats.append(moment.beat)
        }
        return (beats.min() ?? beats[0])...(beats.max() ?? beats[0])
    }

    private func updateParticipation(
        observedPitch: UInt8,
        at momentIndex: Int,
        in compiled: CompiledReference
    ) {
        leftParticipationEvidence *= 0.97
        rightParticipationEvidence *= 0.97

        let moment = compiled.moments[momentIndex]
        let mask = Self.pitchMask(for: observedPitch)
        let isLeft = moment.leftPitchMask & mask != 0
        let isRight = moment.rightPitchMask & mask != 0
        switch (isLeft, isRight) {
        case (true, true):
            leftParticipationEvidence += 0.5
            rightParticipationEvidence += 0.5
        case (true, false):
            leftParticipationEvidence += 1
        case (false, true):
            rightParticipationEvidence += 1
        case (false, false):
            return
        }

        let stronger = max(leftParticipationEvidence, rightParticipationEvidence)
        let weaker = min(leftParticipationEvidence, rightParticipationEvidence)
        if weaker >= 1.75, stronger / max(weaker, 0.001) <= 3.5 {
            inferredParticipation = .both
        } else if leftParticipationEvidence >= 2.5,
                  leftParticipationEvidence >= rightParticipationEvidence * 3.5 {
            inferredParticipation = .left
        } else if rightParticipationEvidence >= 2.5,
                  rightParticipationEvidence >= leftParticipationEvidence * 3.5 {
            inferredParticipation = .right
        }
    }

    private func updateObservedGestureHistory(using best: Hypothesis) {
        guard best.gestureCount > lastCommittedGestureCount,
              best.lastCompletedGestureMask != 0 else {
            return
        }
        recentObservedGestures.append(best.lastCompletedGestureMask)
        if recentObservedGestures.count > Configuration.maximumRecentGestures {
            recentObservedGestures.removeFirst(
                recentObservedGestures.count - Configuration.maximumRecentGestures
            )
        }
        lastCommittedGestureCount = best.gestureCount
    }

    // MARK: - Viewport policy

    private func viewportRecommendation(
        displayMomentIndex: Int,
        state: TrackingState,
        didReplay: Bool,
        didRelocate: Bool,
        in compiled: CompiledReference
    ) -> ViewportRecommendation {
        let lineOffset = compiled.moments[displayMomentIndex].lineOffset
        let lineIndex = compiled.lines[lineOffset].index

        if didRelocate {
            viewportLineOffset = lineOffset
            return .jump(toLine: lineIndex)
        }

        guard state == .tracking, !didReplay else {
            return .unchanged
        }

        guard let previousLineOffset = viewportLineOffset else {
            viewportLineOffset = lineOffset
            return .unchanged
        }
        guard lineOffset != previousLineOffset else { return .unchanged }

        if lineOffset == previousLineOffset + 1 {
            viewportLineOffset = lineOffset
            return .advance(toLine: lineIndex)
        }

        // A nonlocal change should have been classified as a jump before reaching this point.
        // Holding is safer than issuing an unexplained reverse or multi-line scroll in release
        // builds; the assertion catches violations during development.
        assert(lineOffset < previousLineOffset || lineOffset > previousLineOffset + 1)
        return .unchanged
    }

    private func assertPresentationInvariants(
        previous: Update?,
        current: Update,
        in compiled: CompiledReference
    ) {
        if let previous, current.displayBeat < previous.displayBeat {
            assert(current.didRelocate)
        }

        switch current.viewport {
        case .unchanged:
            break
        case let .advance(toLine: lineIndex):
            assert(!current.didRelocate)
            assert(compiled.lines.contains(where: { $0.index == lineIndex }))
        case let .jump(toLine: lineIndex):
            assert(current.didRelocate)
            assert(compiled.lines.contains(where: { $0.index == lineIndex }))
        }
    }

    // MARK: - Small numeric helpers

    private static func coverage(matched: UInt128, expected: UInt128) -> Double {
        guard expected != 0 else { return 1 }
        return Double((matched & expected).nonzeroBitCount)
            / Double(expected.nonzeroBitCount)
    }

    private static func pitchSetSimilarity(_ lhs: UInt128, _ rhs: UInt128) -> Double {
        let union = lhs | rhs
        guard union != 0 else { return 1 }
        return Double((lhs & rhs).nonzeroBitCount) / Double(union.nonzeroBitCount)
    }

    /// Treats adjacent score ranges as non-overlapping. Engraving measures and lines normally
    /// share a boundary beat; that shared endpoint must not pull the next line into a viewport
    /// hint that ends exactly at the boundary.
    private static func hasPositiveOverlap(
        _ lhs: ClosedRange<Double>,
        _ rhs: ClosedRange<Double>
    ) -> Bool {
        max(lhs.lowerBound, rhs.lowerBound)
            < min(lhs.upperBound, rhs.upperBound) - EngravingReference.simultaneousBeatEpsilon
    }

    private static func valid(_ timestamp: MIDITimeStamp) -> Bool {
        timestamp != 0
    }

    private static func elapsedTicks(
        from earlier: MIDITimeStamp?,
        to later: MIDITimeStamp
    ) -> Double? {
        guard let earlier,
              valid(earlier),
              valid(later),
              later > earlier else {
            return nil
        }
        return Double(later - earlier)
    }

    private static func pitchMask(for pitch: UInt8) -> UInt128 {
        UInt128(1) << UInt128(pitch)
    }

    private static func validRange(_ range: ClosedRange<Double>?) -> ClosedRange<Double>? {
        guard let range,
              range.lowerBound.isFinite,
              range.upperBound.isFinite else {
            return nil
        }
        return range
    }
}
