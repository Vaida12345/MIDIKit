//
//  EngravingScoreFeatures.swift
//  MIDIKit
//

import Foundation


/// Internal hand interpretations. The raw value is also the storage lane in compiled arrays.
enum EngravingHandMode: Int, CaseIterable, Hashable {
    case both
    case left
    case right
}

/// Inline storage for the three hand interpretations. Unlike `[UInt128]`, this does not allocate
/// per score gesture or per MIDI event.
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

struct EngravingScoreGesture {
    let beat: Double
    let measureOffset: Int
    let lineOffset: Int
    let attack: EngravingReference.Attack
    let masks: EngravingPitchMasks
    let averageDurations: SIMD3<Double>
    let lowestPitch: Int
    let highestPitch: Int
    let pitchCentroid: Double
    let bassInterval: Int
    let sopranoInterval: Int
    let beatGap: Double
    let beginsMeasure: Bool
    let beginsLine: Bool

    @inline(__always)
    func mask(for mode: EngravingHandMode) -> UInt128 { masks[mode] }

    @inline(__always)
    func duration(for mode: EngravingHandMode) -> Double { averageDurations[mode.rawValue] }
}

struct EngravingGestureFingerprint: Hashable {
    let first: UInt128
    let second: UInt128
}

/// Read-only, precomputed score representation used on the real-time input path.
struct EngravingScoreFeatureIndex {
    private static let maximumPostingProbeMultiplier = 8

    let measures: [EngravingReference.Measure]
    let lines: [EngravingReference.Line]
    let gestures: [EngravingScoreGesture]
    let lineOffsetByMeasureOffset: [Int]

    private let pitchPostings: [[[Int]]]
    private let exactMaskPostings: [[UInt128: [Int]]]
    private let pairPostings: [[EngravingGestureFingerprint: [Int]]]
    private let nextRelevant: [[Int?]]

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

        var built: [EngravingScoreGesture] = []
        built.reserveCapacity(reference.moments.count)
        for (momentOffset, moment) in reference.moments.enumerated() {
            guard let measureOffset = EngravingReference.measureOffset(
                containing: moment.beat,
                in: reference.measures
            ) else { continue }

            var masks = EngravingPitchMasks()
            var durationTotals = Array(repeating: 0.0, count: EngravingHandMode.allCases.count)
            var durationCounts = Array(repeating: 0, count: EngravingHandMode.allCases.count)
            var pitchTotal = 0
            var lowest = 127
            var highest = 0

            for note in moment.notes {
                let bit = Self.pitchBit(note.pitch)
                masks[.both] |= bit
                durationTotals[EngravingHandMode.both.rawValue] += note.duration
                durationCounts[EngravingHandMode.both.rawValue] += 1
                let mode: EngravingHandMode = note.hand == .left ? .left : .right
                masks[mode] |= bit
                durationTotals[mode.rawValue] += note.duration
                durationCounts[mode.rawValue] += 1
                pitchTotal += Int(note.pitch)
                lowest = min(lowest, Int(note.pitch))
                highest = max(highest, Int(note.pitch))
            }

            let durations = SIMD3<Double>(
                durationTotals[0] / Double(max(1, durationCounts[0])),
                durationTotals[1] / Double(max(1, durationCounts[1])),
                durationTotals[2] / Double(max(1, durationCounts[2]))
            )
            let previous = built.last
            let beginsMeasure = abs(reference.measures[measureOffset].onset - moment.beat)
                <= EngravingReference.beatEpsilon
            let lineOffset = lineByMeasure[measureOffset]
            let beginsLine = abs(reference.lines[lineOffset].beatRange.lowerBound - moment.beat)
                <= EngravingReference.beatEpsilon
            built.append(EngravingScoreGesture(
                beat: moment.beat,
                measureOffset: measureOffset,
                lineOffset: lineOffset,
                attack: moment.attack,
                masks: masks,
                averageDurations: durations,
                lowestPitch: lowest,
                highestPitch: highest,
                pitchCentroid: Double(pitchTotal) / Double(moment.notes.count),
                bassInterval: previous.map { lowest - $0.lowestPitch } ?? 0,
                sopranoInterval: previous.map { highest - $0.highestPitch } ?? 0,
                beatGap: previous.map { moment.beat - $0.beat } ?? 0,
                beginsMeasure: beginsMeasure,
                beginsLine: beginsLine
            ))
            assert(momentOffset == built.count - 1)
        }
        gestures = built

        var postings = Array(
            repeating: Array(repeating: [Int](), count: 128),
            count: EngravingHandMode.allCases.count
        )
        var masks = Array(
            repeating: [UInt128: [Int]](),
            count: EngravingHandMode.allCases.count
        )
        var pairs = Array(
            repeating: [EngravingGestureFingerprint: [Int]](),
            count: EngravingHandMode.allCases.count
        )
        for mode in EngravingHandMode.allCases {
            var previousMask: UInt128?
            for (index, gesture) in built.enumerated() {
                let mask = gesture.mask(for: mode)
                guard mask != 0 else { continue }
                masks[mode.rawValue][mask, default: []].append(index)
                var remaining = mask
                while remaining != 0 {
                    let pitch = remaining.trailingZeroBitCount
                    postings[mode.rawValue][pitch].append(index)
                    remaining &= remaining - 1
                }
                if let previousMask {
                    pairs[mode.rawValue][
                        EngravingGestureFingerprint(first: previousMask, second: mask),
                        default: []
                    ].append(index)
                }
                previousMask = mask
            }
        }
        pitchPostings = postings
        exactMaskPostings = masks
        pairPostings = pairs

        var successors = Array(
            repeating: Array<Int?>(repeating: nil, count: built.count),
            count: EngravingHandMode.allCases.count
        )
        for mode in EngravingHandMode.allCases {
            var next: Int?
            for index in built.indices.reversed() {
                successors[mode.rawValue][index] = next
                if built[index].mask(for: mode) != 0 { next = index }
            }
        }
        nextRelevant = successors
    }

    @inline(__always)
    func successor(of index: Int, mode: EngravingHandMode) -> Int? {
        guard gestures.indices.contains(index) else { return nil }
        return nextRelevant[mode.rawValue][index]
    }

    func secondSuccessor(of index: Int, mode: EngravingHandMode) -> Int? {
        guard let first = successor(of: index, mode: mode) else { return nil }
        return successor(of: first, mode: mode)
    }

    /// Returns score-wide candidates without scanning the score. Exact chords and exact
    /// two-gesture fingerprints are preferred; otherwise the rarest observed pitch posting is
    /// used as the bounded entry point.
    func candidateIndices(
        for observedMask: UInt128,
        previousMask: UInt128?,
        mode: EngravingHandMode,
        limit: Int
    ) -> [Int] {
        guard observedMask != 0 else { return [] }
        if let previousMask,
           let exact = pairPostings[mode.rawValue][
               EngravingGestureFingerprint(first: previousMask, second: observedMask)
           ], !exact.isEmpty {
            return Self.distributedSample(exact, limit: limit)
        }
        if let exact = exactMaskPostings[mode.rawValue][observedMask], !exact.isEmpty {
            return Self.distributedSample(exact, limit: limit)
        }

        var rarest: [Int]?
        var remaining = observedMask
        while remaining != 0 {
            let pitch = remaining.trailingZeroBitCount
            let posting = pitchPostings[mode.rawValue][pitch]
            if !posting.isEmpty, posting.count < (rarest?.count ?? .max) { rarest = posting }
            remaining &= remaining - 1
        }
        guard let rarest else { return [] }
        if rarest.count <= limit { return rarest }

        // A wrong extra tone can defeat exact-mask lookup, and a ubiquitous pitch can have a
        // posting proportional to the whole score. Probe a score-wide, evenly distributed
        // subset so malformed or ambiguous input never turns one MIDI event into a full-score
        // scan. Exact chords and exact two-gesture fingerprints remain lossless above.
        let maximumProbes = max(limit, limit * Self.maximumPostingProbeMultiplier)
        let probes = rarest.count > maximumProbes
            ? Self.distributedSample(rarest, limit: maximumProbes)
            : rarest

        var ranked: [(index: Int, quality: Double)] = []
        ranked.reserveCapacity(limit)
        for index in probes {
            let candidate = (
                index,
                Self.pitchSimilarity(observedMask, gestures[index].mask(for: mode))
            )
            let insertion = ranked.firstIndex {
                candidate.1 > $0.quality || (candidate.1 == $0.quality && index < $0.index)
            } ?? ranked.endIndex
            if insertion < limit {
                ranked.insert(candidate, at: insertion)
                if ranked.count > limit { ranked.removeLast() }
            } else if ranked.count < limit {
                ranked.append(candidate)
            }
        }
        return ranked.map(\.index)
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

    func measureOffsets(intersecting range: ClosedRange<Double>) -> ClosedRange<Int>? {
        var lower: Int?
        var upper: Int?
        let point = range.upperBound - range.lowerBound <= EngravingReference.beatEpsilon
        for (offset, measure) in measures.enumerated() {
            let overlaps = point
                ? measure.beatRange.contains(range.lowerBound)
                : max(measure.onset, range.lowerBound)
                    < min(measure.onset + measure.duration, range.upperBound)
                        - EngravingReference.beatEpsilon
            if overlaps {
                lower = lower ?? offset
                upper = offset
            }
        }
        guard let lower, let upper else { return nil }
        return lower...upper
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
        guard values.count > limit, limit > 1 else { return Array(values.prefix(limit)) }
        var result: [Int] = []
        result.reserveCapacity(limit)
        let scale = Double(values.count - 1) / Double(limit - 1)
        for offset in 0..<limit {
            result.append(values[Int((Double(offset) * scale).rounded())])
        }
        return result
    }
}
