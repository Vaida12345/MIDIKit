//
//  EngravingScoreFeatures.swift
//  MIDIKit
//

import Foundation


/// The performed-hand interpretation carried by an alignment hypothesis.
enum EngravingHandMode: Int, CaseIterable, Hashable {
    case both
    case left
    case right
}

/// Allocation-free storage for the three performed-hand interpretations.
struct EngravingPitchMasks {
    var both: UInt128 = 0
    var left: UInt128 = 0
    var right: UInt128 = 0

    @inline(__always)
    subscript(mode: EngravingHandMode) -> UInt128 {
        get {
            switch mode {
            case .both: both
            case .left: left
            case .right: right
            }
        }
        set {
            switch mode {
            case .both: both = newValue
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }
}

struct EngravingCompiledNote: Hashable {
    let pitch: UInt8
    let duration: Double
    let hand: EngravingReference.Hand
}

struct EngravingScoreGesture {
    let beat: Double
    let measureOffset: Int
    let lineOffset: Int
    let attack: EngravingReference.Attack
    let notes: [EngravingCompiledNote]
    let masks: EngravingPitchMasks
    let beginsMeasure: Bool
    let beginsLine: Bool

    @inline(__always)
    func mask(for mode: EngravingHandMode) -> UInt128 { masks[mode] }

    func duration(of pitch: UInt8, mode: EngravingHandMode) -> Double? {
        var result: Double?
        for note in notes where note.pitch == pitch {
            let included = mode == .both
                || (mode == .left && note.hand == .left)
                || (mode == .right && note.hand == .right)
            if included { result = max(result ?? 0, note.duration) }
        }
        return result
    }
}

/// A bounded, error-tolerant score lookup. `isExhaustive` is deliberately propagated into
/// relocation decisions: pruning repeated occurrences must never manufacture certainty.
struct EngravingCandidateLookup {
    let indices: [Int]
    let isExhaustive: Bool
    /// True when every candidate in `preferredRange` was retained. This is separate from global
    /// exhaustiveness so acquisition may use a bounded score-wide lookup without pretending that
    /// omitted candidates inside the user's current frame have been disambiguated.
    let preferredRangeIsExhaustive: Bool
}

/// Immutable score features used by the real-time alignment path.
struct EngravingScoreFeatureIndex {
    private static let maximumPostingProbeMultiplier = 6

    let measures: [EngravingReference.Measure]
    let lines: [EngravingReference.Line]
    let gestures: [EngravingScoreGesture]
    let lineOffsetByMeasureOffset: [Int]

    private let pitchPostings: [[[Int]]]
    private let exactMaskPostings: [[UInt128: [Int]]]
    private let nextRelevant: [[Int?]]
    private let previousRelevant: [[Int?]]

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

        gestures = reference.moments.compactMap { moment in
            guard let measureOffset = EngravingReference.measureOffset(
                containing: moment.beat,
                in: reference.measures
            ) else { return nil }

            var masks = EngravingPitchMasks()
            let notes = moment.notes.map { note in
                let bit = Self.pitchBit(note.pitch)
                masks[.both] |= bit
                masks[note.hand == .left ? .left : .right] |= bit
                return EngravingCompiledNote(
                    pitch: note.pitch,
                    duration: note.duration,
                    hand: note.hand
                )
            }
            let lineOffset = lineByMeasure[measureOffset]
            return EngravingScoreGesture(
                beat: moment.beat,
                measureOffset: measureOffset,
                lineOffset: lineOffset,
                attack: moment.attack,
                notes: notes,
                masks: masks,
                beginsMeasure: abs(reference.measures[measureOffset].onset - moment.beat)
                    <= EngravingReference.beatEpsilon,
                beginsLine: abs(reference.lines[lineOffset].beatRange.lowerBound - moment.beat)
                    <= EngravingReference.beatEpsilon
            )
        }

        var postings = Array(
            repeating: Array(repeating: [Int](), count: 128),
            count: EngravingHandMode.allCases.count
        )
        var exact = Array(
            repeating: [UInt128: [Int]](),
            count: EngravingHandMode.allCases.count
        )
        for mode in EngravingHandMode.allCases {
            for (index, gesture) in gestures.enumerated() {
                let mask = gesture.mask(for: mode)
                guard mask != 0 else { continue }
                exact[mode.rawValue][mask, default: []].append(index)
                var remaining = mask
                while remaining != 0 {
                    let pitch = remaining.trailingZeroBitCount
                    postings[mode.rawValue][pitch].append(index)
                    remaining &= remaining - 1
                }
            }
        }
        pitchPostings = postings
        exactMaskPostings = exact

        var successors = Array(
            repeating: Array<Int?>(repeating: nil, count: gestures.count),
            count: EngravingHandMode.allCases.count
        )
        var predecessors = successors
        for mode in EngravingHandMode.allCases {
            var next: Int?
            for index in gestures.indices.reversed() {
                successors[mode.rawValue][index] = next
                if gestures[index].mask(for: mode) != 0 { next = index }
            }
            var previous: Int?
            for index in gestures.indices {
                predecessors[mode.rawValue][index] = previous
                if gestures[index].mask(for: mode) != 0 { previous = index }
            }
        }
        nextRelevant = successors
        previousRelevant = predecessors
    }

    @inline(__always)
    func successor(of index: Int, mode: EngravingHandMode) -> Int? {
        guard gestures.indices.contains(index) else { return nil }
        return nextRelevant[mode.rawValue][index]
    }

    @inline(__always)
    func predecessor(of index: Int, mode: EngravingHandMode) -> Int? {
        guard gestures.indices.contains(index) else { return nil }
        return previousRelevant[mode.rawValue][index]
    }

    func successors(of index: Int, mode: EngravingHandMode, limit: Int) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(limit)
        var cursor = index
        while result.count < limit, let next = successor(of: cursor, mode: mode) {
            result.append(next)
            cursor = next
        }
        return result
    }

    /// Combines bounded postings from every observed pitch. This is intentionally a union, not
    /// an intersection or rarest-pitch lookup: an accidental rare tone cannot exclude the true
    /// score location before the probabilistic emission model gets to judge it.
    func candidateLookup(
        for observedMask: UInt128,
        mode: EngravingHandMode,
        limit: Int,
        preferredRange: ClosedRange<Double>? = nil
    ) -> EngravingCandidateLookup {
        guard observedMask != 0, limit > 0 else {
            return EngravingCandidateLookup(
                indices: [],
                isExhaustive: true,
                preferredRangeIsExhaustive: true
            )
        }

        let probeLimit = max(limit, limit * Self.maximumPostingProbeMultiplier)
        var union = Set<Int>()
        var preferred = Set<Int>()
        var exhaustive = true
        var preferredExhaustive = true
        var remaining = observedMask
        while remaining != 0 {
            let pitch = remaining.trailingZeroBitCount
            let posting = pitchPostings[mode.rawValue][pitch]
            if posting.count > probeLimit { exhaustive = false }
            union.formUnion(Self.distributedSample(posting, limit: probeLimit))
            if let preferredRange {
                let isPoint = preferredRange.upperBound - preferredRange.lowerBound
                    <= EngravingReference.beatEpsilon
                let lower = Self.lowerBound(in: posting) {
                    gestures[$0].beat >= preferredRange.lowerBound - EngravingReference.beatEpsilon
                }
                let upper = Self.lowerBound(in: posting) {
                    gestures[$0].beat >= preferredRange.upperBound
                        + (isPoint
                            ? EngravingReference.beatEpsilon
                            : -EngravingReference.beatEpsilon)
                }
                let visible = posting[lower..<upper]
                let sample = Self.distributedSample(visible, limit: limit)
                preferred.formUnion(sample)
                union.formUnion(sample)
                if visible.count > limit {
                    exhaustive = false
                    preferredExhaustive = false
                }
            }
            remaining &= remaining - 1
        }

        // Exact masks are useful candidates, but never an exclusive fast path: a serialized
        // attack is generally only a partial observation of a performed onset.
        if let exact = exactMaskPostings[mode.rawValue][observedMask] {
            union.formUnion(Self.distributedSample(exact, limit: probeLimit))
            if exact.count > probeLimit { exhaustive = false }
        }

        let ranked = union.map { index in
            (index: index, quality: Self.pitchSimilarity(
                observedMask,
                gestures[index].mask(for: mode)
            ))
        }.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            return $0.index < $1.index
        }

        let selected: [(index: Int, quality: Double)]
        if preferredRange != nil, !preferred.isEmpty {
            let preferredRanked = ranked.filter { preferred.contains($0.index) }
            let scoreWideRanked = ranked.filter { !preferred.contains($0.index) }

            if scoreWideRanked.isEmpty {
                selected = Array(preferredRanked.prefix(limit))
            } else {
                // Visibility reserves bounded capacity but never consumes the whole lookup. Music
                // outside the frame must remain able to overcome the acquisition prior.
                let preferredCapacity = max(1, limit / 2)
                var chosen = Array(preferredRanked.prefix(preferredCapacity))
                let selectedPreferredCount = chosen.count
                chosen += scoreWideRanked.prefix(limit - chosen.count)
                if chosen.count < limit {
                    chosen += preferredRanked.dropFirst(selectedPreferredCount)
                        .prefix(limit - chosen.count)
                }
                selected = chosen
            }
            if preferredRanked.count > selected.reduce(0, {
                $0 + (preferred.contains($1.index) ? 1 : 0)
            }) {
                preferredExhaustive = false
            }
        } else {
            selected = Array(ranked.prefix(limit))
        }

        if ranked.count > selected.count {
            exhaustive = false
        }
        return EngravingCandidateLookup(
            indices: selected.map(\.index),
            isExhaustive: exhaustive,
            preferredRangeIsExhaustive: preferredExhaustive
        )
    }

    @inline(__always)
    func isVisible(_ gestureIndex: Int, in range: ClosedRange<Double>?) -> Bool {
        guard let range, gestures.indices.contains(gestureIndex) else { return false }
        let beat = gestures[gestureIndex].beat
        if range.upperBound - range.lowerBound <= EngravingReference.beatEpsilon {
            return abs(beat - range.lowerBound) <= EngravingReference.beatEpsilon
        }
        return beat >= range.lowerBound - EngravingReference.beatEpsilon
            && beat < range.upperBound - EngravingReference.beatEpsilon
    }

    /// Returns the furthest committed marker that can be shown on one intermediate line. The
    /// binary search keeps presentation catch-up bounded even for very long scores.
    func lastGestureIndex(onLine lineOffset: Int, atOrBefore upperIndex: Int) -> Int? {
        guard lines.indices.contains(lineOffset), gestures.indices.contains(upperIndex) else {
            return nil
        }
        var lower = gestures.startIndex
        var upper = gestures.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if gestures[middle].lineOffset <= lineOffset { lower = middle + 1 }
            else { upper = middle }
        }
        let candidate = min(upperIndex, lower - 1)
        guard gestures.indices.contains(candidate),
              gestures[candidate].lineOffset == lineOffset else { return nil }
        return candidate
    }

    /// A region-level prior whose total probability is independent of how many repeated score
    /// moments happen to exist on or off screen. A flat per-candidate bonus would let a long score
    /// overwhelm the viewport merely by containing more occurrences of a common pitch.
    func acquisitionLogPrior(
        for gestureIndex: Int,
        in range: ClosedRange<Double>?
    ) -> Double {
        guard let range, gestures.indices.contains(gestureIndex) else { return 0 }
        let isPoint = range.upperBound - range.lowerBound <= EngravingReference.beatEpsilon
        let lower = Self.lowerBoundGesture(in: gestures) {
            $0.beat >= range.lowerBound - EngravingReference.beatEpsilon
        }
        let upper = Self.lowerBoundGesture(in: gestures) {
            $0.beat >= range.upperBound
                + (isPoint ? EngravingReference.beatEpsilon : -EngravingReference.beatEpsilon)
        }
        let visibleCount = upper - lower
        guard visibleCount > 0 else { return 0 }
        let offscreenCount = max(1, gestures.count - visibleCount)
        return isVisible(gestureIndex, in: range)
            ? Foundation.log(0.82 / Double(visibleCount))
            : Foundation.log(0.18 / Double(offscreenCount))
    }

    static func pitchSimilarity(_ observed: UInt128, _ expected: UInt128) -> Double {
        guard observed != 0, expected != 0 else { return 0 }
        let intersection = (observed & expected).nonzeroBitCount
        guard intersection > 0 else { return 0 }
        let precision = Double(intersection) / Double(observed.nonzeroBitCount)
        let recall = Double(intersection) / Double(expected.nonzeroBitCount)
        return 2 * precision * recall / (precision + recall)
    }

    @inline(__always)
    static func pitchBit(_ pitch: UInt8) -> UInt128 { UInt128(1) << UInt128(pitch) }

    private static func distributedSample<Values>(
        _ values: Values,
        limit: Int
    ) -> [Int] where Values: RandomAccessCollection, Values.Element == Int {
        guard values.count > limit, limit > 1 else { return Array(values.prefix(max(0, limit))) }
        var result: [Int] = []
        result.reserveCapacity(limit)
        let scale = Double(values.count - 1) / Double(limit - 1)
        for offset in 0..<limit {
            let index = values.index(
                values.startIndex,
                offsetBy: Int((Double(offset) * scale).rounded())
            )
            result.append(values[index])
        }
        return result
    }

    private static func lowerBound(
        in values: [Int],
        where predicate: (Int) -> Bool
    ) -> Int {
        var lower = values.startIndex
        var upper = values.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if predicate(values[middle]) { upper = middle }
            else { lower = middle + 1 }
        }
        return lower
    }

    private static func lowerBoundGesture(
        in values: [EngravingScoreGesture],
        where predicate: (EngravingScoreGesture) -> Bool
    ) -> Int {
        var lower = values.startIndex
        var upper = values.endIndex
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if predicate(values[middle]) { upper = middle }
            else { lower = middle + 1 }
        }
        return lower
    }
}
