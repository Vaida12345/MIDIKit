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
        limit: Int
    ) -> EngravingCandidateLookup {
        guard observedMask != 0, limit > 0 else {
            return EngravingCandidateLookup(indices: [], isExhaustive: true)
        }

        if let exact = exactMaskPostings[mode.rawValue][observedMask], !exact.isEmpty {
            return EngravingCandidateLookup(
                indices: Self.distributedSample(exact, limit: limit),
                isExhaustive: exact.count <= limit
            )
        }

        let probeLimit = max(limit, limit * Self.maximumPostingProbeMultiplier)
        var union = Set<Int>()
        var exhaustive = true
        var remaining = observedMask
        while remaining != 0 {
            let pitch = remaining.trailingZeroBitCount
            let posting = pitchPostings[mode.rawValue][pitch]
            if posting.count > probeLimit { exhaustive = false }
            union.formUnion(Self.distributedSample(posting, limit: probeLimit))
            remaining &= remaining - 1
        }

        var ranked = union.map { index in
            (index: index, quality: Self.pitchSimilarity(
                observedMask,
                gestures[index].mask(for: mode)
            ))
        }
        ranked.sort {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            return $0.index < $1.index
        }
        if ranked.count > limit {
            exhaustive = false
            ranked.removeLast(ranked.count - limit)
        }
        return EngravingCandidateLookup(indices: ranked.map(\.index), isExhaustive: exhaustive)
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

    private static func distributedSample(_ values: [Int], limit: Int) -> [Int] {
        guard values.count > limit, limit > 1 else { return Array(values.prefix(max(0, limit))) }
        var result: [Int] = []
        result.reserveCapacity(limit)
        let scale = Double(values.count - 1) / Double(limit - 1)
        for offset in 0..<limit {
            result.append(values[Int((Double(offset) * scale).rounded())])
        }
        return result
    }
}
