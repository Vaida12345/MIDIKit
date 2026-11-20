//
//  Notes+Similarity.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//


extension MIDINotes {

    /// Measures how similar these notes are to `other`, by their onsets and offsets.
    ///
    /// The score is a soft F1: notes are paired, and each pair counts by how close it is instead of counting as a whole match.
    ///
    /// 1. Only notes of the same pitch are paired. A note with the wrong pitch is a miss on one side and an extra note on the other.
    /// 2. A pair counts with the weight `w = max(0, 1 − e²)`, where `e² = (Δonset / onsetTolerance)² + (Δoffset / τₒff)²`. The offset tolerance grows with the note, `τₒff = max(onsetTolerance, offsetToleranceRatio × d̄)`, where `d̄` is the mean duration of the two notes: the release of a long note is less precise than that of a short one.
    /// 3. On each pitch, notes are paired in time order to maximize the sum of the weights. A note is paired at most once, and a pair whose weight is 0 is never formed.
    /// 4. The score is `2 Σw / (n + m)`, where `n` and `m` are the numbers of notes on each side.
    ///
    /// The score is symmetric, in `0...1`: 1 when the notes are the same, and 0 when no note has a counterpart within the tolerances. When every pair is either exact or beyond the tolerances, it is exactly the F1 score, `2 × matched / (n + m)`. The defaults match the note-level evaluation of transcriptions in mir_eval: onsets within 50 ms, and offsets within 20% of the duration. All times are in beats, so the default onset tolerance, 0.1 beat, is 50 ms at 120 BPM.
    ///
    /// Velocity is ignored. Notes whose onset or offset is not finite are never paired.
    ///
    /// - Parameters:
    ///   - other: The notes to compare with. The notes need not be sorted.
    ///   - onsetTolerance: The onset difference, in beats, at which a pair stops counting. It must be finite and greater than zero.
    ///   - offsetToleranceRatio: The offset tolerance, as a fraction of the mean duration of a pair. It must be finite and not negative. The offset tolerance is never less than `onsetTolerance`.
    ///
    /// - Complexity: O(*n* log *n*), where *n* is the number of notes, when notes on the same key are at least `onsetTolerance` apart. A key struck *k* times in a row at shorter intervals costs O(*k*²).
    public func similarity(to other: MIDINotes, onsetTolerance: Double = 0.1, offsetToleranceRatio: Double = 0.2) -> Similarity {
        precondition(onsetTolerance.isFinite && onsetTolerance > 0, "onsetTolerance must be finite and greater than zero")
        precondition(offsetToleranceRatio.isFinite && offsetToleranceRatio >= 0, "offsetToleranceRatio must be finite and not negative")

        let lhs = self.contents
        let rhs = other.contents
        let total = lhs.count &+ rhs.count
        guard total > 0 else {
            return Similarity(score: 1, matchedCount: 0, unmatchedCount: 0, otherUnmatchedCount: 0, onsetRMSE: nil, offsetRMSE: nil)
        }

        let (lhsOrder, lhsStarts) = Self.groupedByKey(lhs)
        let (rhsOrder, rhsStarts) = Self.groupedByKey(rhs)

        var weightSum = 0.0
        var matchedCount = 0
        var onsetSquares = 0.0
        var offsetSquares = 0.0

        // Reused across clusters: the best sums, and the step that led to each.
        var best: [Double] = []
        var steps: [Step] = []

        /// Pairs `lhsOrder[l0..<l1]` with `rhsOrder[r0..<r1]`, which lie on one key and in one cluster.
        func align(_ l0: Int, _ l1: Int, _ r0: Int, _ r1: Int) {
            let rows = l1 &- l0
            let columns = r1 &- r0
            guard rows > 0 && columns > 0 else { return }
            let width = columns &+ 1
            let size = (rows &+ 1) &* width
            if best.count < size {
                best = [Double](repeating: 0, count: size)
                steps = [Step](repeating: .skipLeft, count: size)
            }

            var j = 0
            while j <= columns {
                best[j] = 0
                steps[j] = .skipRight
                j &+= 1
            }

            var i = 1
            while i <= rows {
                let row = i &* width
                best[row] = 0
                steps[row] = .skipLeft
                let left = lhs[lhsOrder[l0 &+ i &- 1]]
                j = 1
                while j <= columns {
                    let up = best[row &- width &+ j]
                    let back = best[row &+ j &- 1]
                    var value = up
                    var step = Step.skipLeft
                    if back > value {
                        value = back
                        step = .skipRight
                    }
                    let pair = Self.pairWeight(left, rhs[rhsOrder[r0 &+ j &- 1]], onsetTolerance: onsetTolerance, offsetToleranceRatio: offsetToleranceRatio)
                    if pair > 0 {
                        let diagonal = best[row &- width &+ j &- 1] + pair
                        if diagonal > value {
                            value = diagonal
                            step = .pair
                        }
                    }
                    best[row &+ j] = value
                    steps[row &+ j] = step
                    j &+= 1
                }
                i &+= 1
            }

            // Trace the best pairing back.
            i = rows
            j = columns
            while i > 0 && j > 0 {
                switch steps[i &* width &+ j] {
                case .pair:
                    let left = lhs[lhsOrder[l0 &+ i &- 1]]
                    let right = rhs[rhsOrder[r0 &+ j &- 1]]
                    weightSum += Self.pairWeight(left, right, onsetTolerance: onsetTolerance, offsetToleranceRatio: offsetToleranceRatio)
                    matchedCount &+= 1
                    let onsetError = left.onset - right.onset
                    let offsetError = left.offset - right.offset
                    onsetSquares += onsetError * onsetError
                    offsetSquares += offsetError * offsetError
                    i &-= 1
                    j &-= 1
                case .skipLeft:
                    i &-= 1
                case .skipRight:
                    j &-= 1
                }
            }
        }

        // MARK: Split each key into clusters that no pair can cross.

        var key = 0
        while key < 256 {
            let lEnd = lhsStarts[key &+ 1]
            let rEnd = rhsStarts[key &+ 1]
            var l = lhsStarts[key]
            var r = rhsStarts[key]

            if l < lEnd && r < rEnd {
                var l0 = l
                var r0 = r
                var previous = -Double.infinity
                // Walk both lists by onset; a gap of at least `onsetTolerance` ends a cluster, as no pair can span it.
                while l < lEnd || r < rEnd {
                    let takeLeft = r == rEnd || (l < lEnd && lhs[lhsOrder[l]].onset <= rhs[rhsOrder[r]].onset)
                    let onset = takeLeft ? lhs[lhsOrder[l]].onset : rhs[rhsOrder[r]].onset
                    if onset - previous >= onsetTolerance {
                        align(l0, l, r0, r)
                        l0 = l
                        r0 = r
                    }
                    previous = onset
                    if takeLeft { l &+= 1 } else { r &+= 1 }
                }
                align(l0, l, r0, r)
            }
            key &+= 1
        }

        let onsetRMSE = matchedCount > 0 ? (onsetSquares / Double(matchedCount)).squareRoot() : nil
        let offsetRMSE = matchedCount > 0 ? (offsetSquares / Double(matchedCount)).squareRoot() : nil
        return Similarity(
            score: Swift.min(1, 2 * weightSum / Double(total)),
            matchedCount: matchedCount,
            unmatchedCount: lhs.count &- matchedCount,
            otherUnmatchedCount: rhs.count &- matchedCount,
            onsetRMSE: onsetRMSE,
            offsetRMSE: offsetRMSE
        )
    }


    /// The result of ``MIDINotes/similarity(to:onsetTolerance:offsetToleranceRatio:)``.
    public struct Similarity: Sendable, Hashable {

        /// The soft F1 score, in `0...1`: 1 when the notes are the same, 0 when no note has a counterpart.
        public let score: Double

        /// The number of pairs, each a note of either side within the tolerances of the other.
        public let matchedCount: Int

        /// The number of notes of the receiver without a counterpart in `other`.
        public let unmatchedCount: Int

        /// The number of notes of `other` without a counterpart in the receiver.
        public let otherUnmatchedCount: Int

        /// The root mean square of the onset differences of the pairs, in beats, or `nil` when nothing is paired.
        public let onsetRMSE: Double?

        /// The root mean square of the offset differences of the pairs, in beats, or `nil` when nothing is paired.
        public let offsetRMSE: Double?

    }


    /// A step of the alignment of the notes on one key.
    private enum Step: UInt8 {
        /// The receiver's note is left without a counterpart.
        case skipLeft
        /// The other side's note is left without a counterpart.
        case skipRight
        /// The two notes are paired.
        case pair
    }

    /// The weight of pairing two notes of the same key, `max(0, 1 − e²)`.
    private static func pairWeight(_ lhs: MIDINote, _ rhs: MIDINote, onsetTolerance: Double, offsetToleranceRatio: Double) -> Double {
        let onsetError = (lhs.onset - rhs.onset) / onsetTolerance
        guard onsetError * onsetError < 1 else { return 0 }
        let meanDuration = (Swift.max(0, lhs.offset - lhs.onset) + Swift.max(0, rhs.offset - rhs.onset)) / 2
        let offsetTolerance = Swift.max(onsetTolerance, offsetToleranceRatio * meanDuration)
        let offsetError = (lhs.offset - rhs.offset) / offsetTolerance
        return Swift.max(0, 1 - onsetError * onsetError - offsetError * offsetError)
    }

    /// The indices of the notes with finite times, grouped by key and sorted by (onset, offset) within each key.
    ///
    /// - Returns: The indices, and where each key starts: the notes of key `k` are at `order[starts[k]..<starts[k + 1]]`.
    private static func groupedByKey(_ notes: [MIDINote]) -> (order: [Int], starts: [Int]) {
        var starts = [Int](repeating: 0, count: 257)
        var index = 0
        while index < notes.count {
            let note = notes[index]
            if note.onset.isFinite && note.offset.isFinite {
                starts[Int(note.pitch) &+ 1] &+= 1
            }
            index &+= 1
        }
        var key = 1
        while key < starts.count {
            starts[key] &+= starts[key &- 1]
            key &+= 1
        }

        var cursors = starts
        var order = [Int](repeating: 0, count: starts[256])
        index = 0
        while index < notes.count {
            let note = notes[index]
            if note.onset.isFinite && note.offset.isFinite {
                order[cursors[Int(note.pitch)]] = index
                cursors[Int(note.pitch)] &+= 1
            }
            index &+= 1
        }

        key = 0
        while key < 256 {
            order[starts[key]..<starts[key &+ 1]].sort { lhs, rhs in
                let left = notes[lhs]
                let right = notes[rhs]
                return left.onset < right.onset || (left.onset == right.onset && left.offset < right.offset)
            }
            key &+= 1
        }
        return (order, starts)
    }

}
