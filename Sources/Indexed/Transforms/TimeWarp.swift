//
//  TimeWarp.swift
//  MIDIKit
//
//  Created by Vaida on 2026-04-02.
//

import Foundation
import Accelerate

extension IndexedContainer {

    /// Creates a time warp between `self` and `other` using default parameters.
    /// - Complexity: O(nA log nA + nB log nB + NA * NB), where n* are note counts and N* are chord-event counts.
    public func timeWarp(other: IndexedContainer) -> TimeWarpMapping {
        self.timeWarp(other: other, parameters: .init())
    }

    /// Creates a time warp between `self` and `other`.
    ///
    /// The method performs a two-pass chord-event alignment with semiglobal affine-gap dynamic programming,
    /// then fits a robust monotone piecewise-linear mapping.
    ///
    /// - Parameters:
    ///   - other: Target container to project into.
    ///   - parameters: Alignment and fitting controls.
    /// - Returns: A mapping function from this container's beat timeline to `other`'s beat timeline.
    /// - Complexity: O(nA log nA + nB log nB + NA * NB), where n* are note counts and N* are chord-event counts.
    public func timeWarp(other: IndexedContainer, parameters: TimeWarpParameters = .init()) -> TimeWarpMapping {
        guard !self.isEmpty, !other.isEmpty else { return .identity }

        let eventsA = Self.noteOnEvents(from: self)
        let eventsB = Self.noteOnEvents(from: other)
        guard !eventsA.isEmpty, !eventsB.isEmpty else { return .identity }

        let epsilonA = parameters.epsilonA ?? Self.estimatedChordWindow(from: eventsA)
        let epsilonB = parameters.epsilonB ?? Self.estimatedChordWindow(from: eventsB)
        let duplicateA = parameters.duplicateMergeThresholdA ?? Swift.min(0.01, epsilonA / 4)
        let duplicateB = parameters.duplicateMergeThresholdB ?? Swift.min(0.01, epsilonB / 4)

        let cleanA = Self.cleanedEvents(eventsA, duplicateThreshold: duplicateA)
        let cleanB = Self.cleanedEvents(eventsB, duplicateThreshold: duplicateB)

        let chordsA = Self.chordEvents(from: cleanA, epsilon: epsilonA)
        let chordsB = Self.chordEvents(from: cleanB, epsilon: epsilonB)
        guard !chordsA.isEmpty, !chordsB.isEmpty else {
            return Self.endpointLinearFallback(lhs: cleanA, rhs: cleanB)
        }

        let pass1 = Self.alignAffineSemiglobal(
            lhs: chordsA,
            rhs: chordsB,
            gapOpen: parameters.gapOpen,
            gapExtend: parameters.gapExtend,
            score: { i, j in
                let metrics = Self.overlapMetrics(chordsA[i].pitches, chordsB[j].pitches)
                if !Self.isAllowedInPass1(metrics, lhsCount: chordsA[i].pitches.count, rhsCount: chordsB[j].pitches.count, tauDice1: parameters.tauDice1) {
                    return -Double.infinity
                }

                return parameters.overlapReward * Double(metrics.intersection)
                    - parameters.mismatchPenalty * Double(metrics.symmetricDifference)
            }
        )

        let pass1Matches = Self.extractMatches(from: pass1.operations)
        let roughAnchors = Self.anchors(
            from: pass1Matches,
            lhs: chordsA,
            rhs: chordsB,
            tau: parameters.tauDice1,
            fallbackTau: parameters.tauDice2
        )

        let roughWarp = Self.roughWarp(
            anchors: roughAnchors,
            lhs: chordsA,
            rhs: chordsB,
            slopeMin: parameters.slopeMin,
            slopeMax: parameters.slopeMax
        )

        let pass1Residuals = roughAnchors.map { $0.y - roughWarp.map($0.x) }
        let sigmaT: Double = {
            if let mad = Self.mad(pass1Residuals) {
                return Swift.max(0.05, 1.4826 * mad)
            }
            return 0.10
        }()
        let timeGate = Swift.max(0.5, 4 * sigmaT)

        let pass2 = Self.alignAffineSemiglobal(
            lhs: chordsA,
            rhs: chordsB,
            gapOpen: parameters.gapOpen,
            gapExtend: parameters.gapExtend,
            score: { i, j in
                let metrics = Self.overlapMetrics(chordsA[i].pitches, chordsB[j].pitches)
                if !Self.isAllowedInPass2(metrics, lhsCount: chordsA[i].pitches.count, rhsCount: chordsB[j].pitches.count, tauDice2: parameters.tauDice2) {
                    return -Double.infinity
                }

                let pitchScore = parameters.overlapReward * Double(metrics.intersection)
                    - parameters.mismatchPenalty * Double(metrics.symmetricDifference)

                let residual = chordsB[j].time - roughWarp.map(chordsA[i].time)
                if abs(residual) > timeGate {
                    return -Double.infinity
                }

                let z = residual / sigmaT
                return pitchScore - parameters.timingWeight * Self.huber(z, delta: 2)
            }
        )

        let finalMatches = Self.extractMatches(from: pass2.operations)
        var finalAnchors = Self.anchors(
            from: finalMatches,
            lhs: chordsA,
            rhs: chordsB,
            tau: parameters.tauDice2,
            fallbackTau: parameters.tauDice2
        )

        if finalAnchors.count < 2 {
            finalAnchors = roughAnchors
        }

        let cleaned = Self.pruneAnchorOutliers(finalAnchors, slopeMin: parameters.slopeMin, slopeMax: parameters.slopeMax)
        let tauFit = parameters.fitTolerance ?? Self.estimatedFitTolerance(cleaned)

        if let warp = Self.fitPiecewiseLinearWarp(cleaned, tauFit: tauFit, slopeMin: parameters.slopeMin, slopeMax: parameters.slopeMax) {
            return warp
        }

        return roughWarp
    }

    /// Parameters used by ``timeWarp(other:parameters:)``.
    public struct TimeWarpParameters: Sendable {

        /// Chord grouping window for source (`self`) in beats.
        ///
        /// - Default: `nil`, computed as `clip(0.25 * q10(IOI), 0.03, 0.10)`.
        /// - Recommended range: `0.03...0.10`.
        public var epsilonA: Double?

        /// Chord grouping window for target (`other`) in beats.
        ///
        /// - Default: `nil`, computed as `clip(0.25 * q10(IOI), 0.03, 0.10)`.
        /// - Recommended range: `0.03...0.10`.
        public var epsilonB: Double?

        /// Same-pitch duplicate merge threshold for source note-ons.
        ///
        /// - Default: `nil`, computed as `min(0.01, epsilonA / 4)`.
        /// - Recommended range: `0.003...0.02`.
        public var duplicateMergeThresholdA: Double?

        /// Same-pitch duplicate merge threshold for target note-ons.
        ///
        /// - Default: `nil`, computed as `min(0.01, epsilonB / 4)`.
        /// - Recommended range: `0.003...0.02`.
        public var duplicateMergeThresholdB: Double?

        /// Pass-1 Dice gate threshold.
        ///
        /// - Default: `0.50`.
        /// - Recommended range: `0.45...0.60`.
        public var tauDice1: Double

        /// Pass-2 Dice gate threshold.
        ///
        /// - Default: `0.34`.
        /// - Recommended range: `0.25...0.40`.
        public var tauDice2: Double

        /// Overlap reward `alpha` in `alpha * I - beta * D`.
        ///
        /// - Default: `2.0`.
        /// - Recommended range: `1.5...3.0`.
        public var overlapReward: Double

        /// Mismatch penalty `beta` in `alpha * I - beta * D`.
        ///
        /// - Default: `0.8`.
        /// - Recommended range: `0.5...1.2`.
        public var mismatchPenalty: Double

        /// Affine gap opening penalty.
        ///
        /// - Default: `2.5`.
        /// - Recommended range: `1.5...4.0`.
        public var gapOpen: Double

        /// Affine gap extension penalty.
        ///
        /// - Default: `0.5`.
        /// - Recommended range: `0.2...1.0`.
        public var gapExtend: Double

        /// Timing penalty weight `lambda_t` for pass-2 Huber residual cost.
        ///
        /// - Default: `1.5`.
        /// - Recommended range: `0.5...3.0`.
        public var timingWeight: Double

        /// Anchor fit tolerance `tau_fit` in beats for piecewise-linear knot insertion.
        ///
        /// - Default: `nil`, estimated as `max(0.08, 2.5 * MAD(residuals))`.
        /// - Recommended range: `0.05...0.20`.
        public var fitTolerance: Double?

        /// Minimum allowable local warp slope.
        ///
        /// - Default: `0.05`.
        /// - Recommended range: broad guardrail.
        public var slopeMin: Double

        /// Maximum allowable local warp slope.
        ///
        /// - Default: `20.0`.
        /// - Recommended range: broad guardrail.
        public var slopeMax: Double

        /// - Complexity: O(1).
        public init(
            epsilonA: Double? = nil,
            epsilonB: Double? = nil,
            duplicateMergeThresholdA: Double? = nil,
            duplicateMergeThresholdB: Double? = nil,
            tauDice1: Double = 0.50,
            tauDice2: Double = 0.34,
            overlapReward: Double = 2.0,
            mismatchPenalty: Double = 0.8,
            gapOpen: Double = 2.5,
            gapExtend: Double = 0.5,
            timingWeight: Double = 1.5,
            fitTolerance: Double? = nil,
            slopeMin: Double = 0.05,
            slopeMax: Double = 20.0
        ) {
            self.epsilonA = epsilonA
            self.epsilonB = epsilonB
            self.duplicateMergeThresholdA = duplicateMergeThresholdA
            self.duplicateMergeThresholdB = duplicateMergeThresholdB
            self.tauDice1 = tauDice1
            self.tauDice2 = tauDice2
            self.overlapReward = overlapReward
            self.mismatchPenalty = mismatchPenalty
            self.gapOpen = gapOpen
            self.gapExtend = gapExtend
            self.timingWeight = timingWeight
            self.fitTolerance = fitTolerance
            self.slopeMin = slopeMin
            self.slopeMax = slopeMax
        }
    }

    public struct TimeWarpMapping: Sendable {

        fileprivate let xs: [Double]
        fileprivate let ys: [Double]
        fileprivate let fallbackSlope: Double

        public static let identity = TimeWarpMapping(xs: [0], ys: [0], fallbackSlope: 1)

        /// - Complexity: O(1).
        fileprivate init(xs: [Double], ys: [Double], fallbackSlope: Double = 1) {
            self.xs = xs
            self.ys = ys
            self.fallbackSlope = fallbackSlope
        }

        /// Returns `x` projected onto `other` in beats.
        /// - Complexity: O(log k), where k is the number of warp knots.
        public func map(_ x: Double) -> Double {
            guard !self.xs.isEmpty, self.xs.count == self.ys.count else { return x }

            if self.xs.count == 1 {
                return self.ys[0] + self.fallbackSlope * (x - self.xs[0])
            }

            if x <= self.xs[0] {
                let slope = (self.ys[1] - self.ys[0]) / Swift.max(self.xs[1] - self.xs[0], 1e-9)
                return self.ys[0] + slope * (x - self.xs[0])
            }

            if x >= self.xs[self.xs.count - 1] {
                let last = self.xs.count - 1
                let slope = (self.ys[last] - self.ys[last - 1]) / Swift.max(self.xs[last] - self.xs[last - 1], 1e-9)
                return self.ys[last] + slope * (x - self.xs[last])
            }

            var lo = 0
            var hi = self.xs.count - 2
            while lo <= hi {
                let mid = (lo + hi) / 2
                let x1 = self.xs[mid]
                let x2 = self.xs[mid + 1]
                if x1 <= x, x <= x2 {
                    let t = (x - x1) / Swift.max(x2 - x1, 1e-9)
                    return self.ys[mid] + t * (self.ys[mid + 1] - self.ys[mid])
                }
                if x < x1 {
                    hi = mid - 1
                } else {
                    lo = mid + 1
                }
            }

            return self.ys[self.ys.count - 1]
        }
    }
}

private extension IndexedContainer {

    struct OnsetEvent {
        let time: Double
        let pitch: UInt8
        let originalIndex: Int
    }

    struct ChordEvent {
        let time: Double
        let pitches: Set<UInt8>
    }

    struct Anchor {
        let x: Double
        let y: Double
        let weight: Double
    }

    struct OverlapMetrics {
        let intersection: Int
        let lhsCount: Int
        let rhsCount: Int

        var symmetricDifference: Int {
            (lhsCount - intersection) + (rhsCount - intersection)
        }

        var dice: Double {
            let denominator = lhsCount + rhsCount
            guard denominator > 0 else { return 0 }
            return 2 * Double(intersection) / Double(denominator)
        }
    }

    enum DPState: UInt8 {
        case match = 0
        case gapInRhs = 1
        case gapInLhs = 2
        case start = 3
    }

    enum AlignmentOp {
        case match(Int, Int)
        case deleteLhs(Int)
        case deleteRhs(Int)
    }

    struct AlignmentResult {
        let score: Double
        let operations: [AlignmentOp]
    }

    /// - Complexity: O(n log n), where n is the number of notes in the container.
    static func noteOnEvents(from container: IndexedContainer) -> [OnsetEvent] {
        var events: [OnsetEvent] = []
        events.reserveCapacity(container.contents.count)
        for i in container.contents.indices {
            let note = container.contents[i]
            events.append(OnsetEvent(time: note.onset, pitch: note.note, originalIndex: i))
        }

        events.sort {
            if $0.time != $1.time { return $0.time < $1.time }
            if $0.pitch != $1.pitch { return $0.pitch < $1.pitch }
            return $0.originalIndex < $1.originalIndex
        }

        return events
    }

    /// - Complexity: O(n log n), where n is the number of onset events.
    static func estimatedChordWindow(from events: [OnsetEvent]) -> Double {
        let q10 = q10IOI(from: events) ?? 0.2
        return Swift.max(0.03, Swift.min(0.10, 0.25 * q10))
    }

    /// - Complexity: O(n), where n is the number of onset events.
    static func cleanedEvents(_ events: [OnsetEvent], duplicateThreshold: Double) -> [OnsetEvent] {
        guard !events.isEmpty else { return [] }

        var normalized = events
        for i in 1..<normalized.count {
            if normalized[i].time - normalized[i - 1].time < 1e-6 {
                normalized[i] = OnsetEvent(
                    time: normalized[i - 1].time,
                    pitch: normalized[i].pitch,
                    originalIndex: normalized[i].originalIndex
                )
            }
        }

        var lastOnsetByPitch: [UInt8: Double] = [:]
        var cleaned: [OnsetEvent] = []
        cleaned.reserveCapacity(normalized.count)

        for event in normalized {
            if let previous = lastOnsetByPitch[event.pitch], event.time - previous <= duplicateThreshold {
                continue
            }
            cleaned.append(event)
            lastOnsetByPitch[event.pitch] = event.time
        }

        return cleaned
    }

    /// - Complexity: O(n log n), where n is the number of onset events.
    static func chordEvents(from events: [OnsetEvent], epsilon: Double) -> [ChordEvent] {
        guard !events.isEmpty else { return [] }

        let notes = events.map {
            MIDINote(
                onset: $0.time,
                offset: $0.time + 0.05,
                note: $0.pitch,
                velocity: 64,
                channel: 0,
                releaseVelocity: 0
            )
        }

        let container = MIDIContainer(tracks: [MIDITrack(notes: notes, sustains: [])])
        let indexed = IndexedContainer(container: container, minimumConsecutiveNotesGap: 1e-7)
        let chords = Chord.makeChords(from: indexed, spec: .init(duration: epsilon))

        return chords.map { chord in
            let time = chord.map(\.onset).median ?? chord.leadingOnset
            let pitches = Set(chord.map(\.note))
            return ChordEvent(time: time, pitches: pitches)
        }
    }

    /// - Complexity: O(min(a, b)), where a and b are the pitch-set sizes.
    static func overlapMetrics(_ lhs: Set<UInt8>, _ rhs: Set<UInt8>) -> OverlapMetrics {
        let small = lhs.count <= rhs.count ? lhs : rhs
        let large = lhs.count <= rhs.count ? rhs : lhs

        var intersection = 0
        for note in small where large.contains(note) {
            intersection += 1
        }

        return OverlapMetrics(intersection: intersection, lhsCount: lhs.count, rhsCount: rhs.count)
    }

    /// - Complexity: O(1).
    static func isAllowedInPass1(_ metrics: OverlapMetrics, lhsCount: Int, rhsCount: Int, tauDice1: Double) -> Bool {
        metrics.dice >= tauDice1 || (lhsCount == 1 && rhsCount == 1 && metrics.intersection == 1)
    }

    /// - Complexity: O(1).
    static func isAllowedInPass2(_ metrics: OverlapMetrics, lhsCount: Int, rhsCount: Int, tauDice2: Double) -> Bool {
        metrics.dice >= tauDice2 || (lhsCount == 1 && rhsCount == 1 && metrics.intersection == 1)
    }

    /// - Complexity: O(N * M) time and O(N * M) memory, where N and M are chord-event counts.
    static func alignAffineSemiglobal(
        lhs: [ChordEvent],
        rhs: [ChordEvent],
        gapOpen: Double,
        gapExtend: Double,
        score: (_ i: Int, _ j: Int) -> Double
    ) -> AlignmentResult {
        let n = lhs.count
        let m = rhs.count
        guard n > 0, m > 0 else { return AlignmentResult(score: 0, operations: []) }

        let negativeInfinity = -Double.greatestFiniteMagnitude / 8
        let width = m + 1
        let cellCount = (n + 1) * (m + 1)

        // Complexity: O(1).
        @inline(__always)
        func index(_ i: Int, _ j: Int) -> Int { i * width + j }

        var mMat = Array(repeating: negativeInfinity, count: cellCount)
        var xMat = Array(repeating: negativeInfinity, count: cellCount)
        var yMat = Array(repeating: negativeInfinity, count: cellCount)

        var ptrM = Array(repeating: DPState.start.rawValue, count: cellCount)
        var ptrX = Array(repeating: DPState.start.rawValue, count: cellCount)
        var ptrY = Array(repeating: DPState.start.rawValue, count: cellCount)

        mMat[index(0, 0)] = 0
        for i in 1...n {
            xMat[index(i, 0)] = 0
            ptrX[index(i, 0)] = (i == 1) ? DPState.start.rawValue : DPState.gapInRhs.rawValue
        }
        for j in 1...m {
            yMat[index(0, j)] = 0
            ptrY[index(0, j)] = (j == 1) ? DPState.start.rawValue : DPState.gapInLhs.rawValue
        }

        for i in 1...n {
            for j in 1...m {
                let s = score(i - 1, j - 1)
                let at = index(i, j)

                if s.isFinite {
                    let fromM = mMat[index(i - 1, j - 1)]
                    let fromX = xMat[index(i - 1, j - 1)]
                    let fromY = yMat[index(i - 1, j - 1)]

                    if fromM >= fromX, fromM >= fromY {
                        mMat[at] = fromM + s
                        ptrM[at] = DPState.match.rawValue
                    } else if fromX >= fromY {
                        mMat[at] = fromX + s
                        ptrM[at] = DPState.gapInRhs.rawValue
                    } else {
                        mMat[at] = fromY + s
                        ptrM[at] = DPState.gapInLhs.rawValue
                    }
                }

                let mToX = mMat[index(i - 1, j)] - gapOpen
                let xToX = xMat[index(i - 1, j)] - gapExtend
                let yToX = yMat[index(i - 1, j)] - gapOpen
                if mToX >= xToX, mToX >= yToX {
                    xMat[at] = mToX
                    ptrX[at] = DPState.match.rawValue
                } else if xToX >= yToX {
                    xMat[at] = xToX
                    ptrX[at] = DPState.gapInRhs.rawValue
                } else {
                    xMat[at] = yToX
                    ptrX[at] = DPState.gapInLhs.rawValue
                }

                let mToY = mMat[index(i, j - 1)] - gapOpen
                let yToY = yMat[index(i, j - 1)] - gapExtend
                let xToY = xMat[index(i, j - 1)] - gapOpen
                if mToY >= yToY, mToY >= xToY {
                    yMat[at] = mToY
                    ptrY[at] = DPState.match.rawValue
                } else if yToY >= xToY {
                    yMat[at] = yToY
                    ptrY[at] = DPState.gapInLhs.rawValue
                } else {
                    yMat[at] = xToY
                    ptrY[at] = DPState.gapInRhs.rawValue
                }
            }
        }

        var bestScore = negativeInfinity
        var bestState = DPState.match
        var endI = n
        var endJ = m

        for i in 0...n {
            let candidates: [(Double, DPState)] = [
                (mMat[index(i, m)], .match),
                (xMat[index(i, m)], .gapInRhs),
                (yMat[index(i, m)], .gapInLhs)
            ]
            for candidate in candidates where candidate.0 > bestScore {
                bestScore = candidate.0
                bestState = candidate.1
                endI = i
                endJ = m
            }
        }

        for j in 0...m {
            let candidates: [(Double, DPState)] = [
                (mMat[index(n, j)], .match),
                (xMat[index(n, j)], .gapInRhs),
                (yMat[index(n, j)], .gapInLhs)
            ]
            for candidate in candidates where candidate.0 > bestScore {
                bestScore = candidate.0
                bestState = candidate.1
                endI = n
                endJ = j
            }
        }

        var i = endI
        var j = endJ
        var state = bestState
        var operations: [AlignmentOp] = []
        operations.reserveCapacity(n + m)

        while i > 0 || j > 0 {
            let at = index(i, j)

            switch state {
            case .match:
                guard i > 0, j > 0 else { break }
                operations.append(.match(i - 1, j - 1))
                state = DPState(rawValue: ptrM[at]) ?? .start
                i -= 1
                j -= 1
            case .gapInRhs:
                guard i > 0 else { break }
                operations.append(.deleteLhs(i - 1))
                state = DPState(rawValue: ptrX[at]) ?? .start
                i -= 1
            case .gapInLhs:
                guard j > 0 else { break }
                operations.append(.deleteRhs(j - 1))
                state = DPState(rawValue: ptrY[at]) ?? .start
                j -= 1
            case .start:
                i = 0
                j = 0
            }

            if state == .start {
                break
            }
        }

        operations.reverse()
        return AlignmentResult(score: bestScore, operations: operations)
    }

    /// - Complexity: O(k), where k is the number of alignment operations.
    static func extractMatches(from operations: [AlignmentOp]) -> [(Int, Int)] {
        var matches: [(Int, Int)] = []
        matches.reserveCapacity(operations.count)
        for operation in operations {
            if case let .match(i, j) = operation {
                matches.append((i, j))
            }
        }
        return matches
    }

    /// - Complexity: O(k log k), where k is the number of matched pairs.
    static func anchors(
        from matches: [(Int, Int)],
        lhs: [ChordEvent],
        rhs: [ChordEvent],
        tau: Double,
        fallbackTau: Double
    ) -> [Anchor] {
        // Complexity: O(k log k), where k is the number of matched pairs.
        func build(_ threshold: Double) -> [Anchor] {
            var output: [Anchor] = []
            output.reserveCapacity(matches.count)
            for (i, j) in matches {
                let metrics = overlapMetrics(lhs[i].pitches, rhs[j].pitches)
                if metrics.dice >= threshold {
                    output.append(Anchor(x: lhs[i].time, y: rhs[j].time, weight: metrics.dice))
                }
            }
            return output.sorted { $0.x < $1.x }
        }

        let strict = build(tau)
        if strict.count >= 3 {
            return strict
        }
        return build(fallbackTau)
    }

    /// - Complexity: O(k log k), where k is the number of anchors.
    static func roughWarp(
        anchors: [Anchor],
        lhs: [ChordEvent],
        rhs: [ChordEvent],
        slopeMin: Double,
        slopeMax: Double
    ) -> TimeWarpMapping {
        var cleaned = pruneAnchorOutliers(anchors, slopeMin: slopeMin, slopeMax: slopeMax)

        if cleaned.count < 2,
           let x0 = lhs.first?.time,
           let x1 = lhs.last?.time,
           let y0 = rhs.first?.time,
           let y1 = rhs.last?.time {
            cleaned = [
                Anchor(x: x0, y: y0, weight: 1),
                Anchor(x: x1, y: y1, weight: 1)
            ]
        }

        guard cleaned.count >= 2 else { return .identity }
        let xs = cleaned.map(\.x)
        let ys = cleaned.map(\.y)
        let slope = (ys[1] - ys[0]) / Swift.max(xs[1] - xs[0], 1e-9)
        return TimeWarpMapping(xs: xs, ys: ys, fallbackSlope: slope)
    }

    /// - Complexity: O(k log k), where k is the number of anchors.
    static func pruneAnchorOutliers(_ anchors: [Anchor], slopeMin: Double, slopeMax: Double) -> [Anchor] {
        guard !anchors.isEmpty else { return [] }
        var anchors = anchors.sorted { $0.x < $1.x }

        // Step 1: merge duplicate x within tolerance.
        var merged: [Anchor] = []
        merged.reserveCapacity(anchors.count)
        for anchor in anchors {
            if let last = merged.last, abs(anchor.x - last.x) < 1e-6 {
                _ = merged.removeLast()
                let weight = last.weight + anchor.weight
                let y = (last.y * last.weight + anchor.y * anchor.weight) / Swift.max(weight, 1e-9)
                merged.append(Anchor(x: last.x, y: y, weight: weight))
            } else {
                merged.append(anchor)
            }
        }
        anchors = merged

        // Step 2: remove impossible/extreme slopes.
        for _ in 0..<3 {
            if anchors.count < 3 { break }
            var changed = false

            var i = 0
            while i + 1 < anchors.count {
                let lhs = anchors[i]
                let rhs = anchors[i + 1]
                let dx = rhs.x - lhs.x
                if dx <= 1e-12 {
                    anchors.remove(at: lhs.weight < rhs.weight ? i : i + 1)
                    changed = true
                    break
                }

                let slope = (rhs.y - lhs.y) / dx
                if slope <= 0 || slope < slopeMin || slope > slopeMax {
                    anchors.remove(at: lhs.weight < rhs.weight ? i : i + 1)
                    changed = true
                    break
                }

                i += 1
            }

            if !changed { break }
        }

        // Step 3: local Hampel cleanup on log-slopes.
        for _ in 0..<2 {
            if anchors.count < 4 { break }

            var slopes: [Double] = []
            slopes.reserveCapacity(anchors.count - 1)
            for i in 0..<(anchors.count - 1) {
                let dx = anchors[i + 1].x - anchors[i].x
                let dy = anchors[i + 1].y - anchors[i].y
                slopes.append(Swift.max(dy / Swift.max(dx, 1e-9), 1e-9))
            }
            let logSlopes = slopes.map { log($0) }

            var changed = false
            for i in logSlopes.indices {
                let start = Swift.max(0, i - 3)
                let end = Swift.min(logSlopes.count - 1, i + 3)
                let window = Array(logSlopes[start...end])
                guard let localMedian = window.median else { continue }

                let localMAD = Swift.max(window.map { abs($0 - localMedian) }.median ?? 0, 0.1)
                if abs(logSlopes[i] - localMedian) > 3 * localMAD {
                    let lhs = anchors[i]
                    let rhs = anchors[i + 1]
                    anchors.remove(at: lhs.weight < rhs.weight ? i : i + 1)
                    changed = true
                    break
                }
            }

            if !changed { break }
        }

        return anchors
    }

    /// - Complexity: O(k log k + s), where k is the number of anchors and s is split recursion work.
    static func fitPiecewiseLinearWarp(_ anchors: [Anchor], tauFit: Double, slopeMin: Double, slopeMax: Double) -> TimeWarpMapping? {
        let anchors = pruneAnchorOutliers(anchors, slopeMin: slopeMin, slopeMax: slopeMax)
        guard !anchors.isEmpty else { return nil }

        if anchors.count == 1 {
            let a = anchors[0]
            return TimeWarpMapping(xs: [a.x], ys: [a.y], fallbackSlope: 1)
        }

        var knots: Set<Int> = [0, anchors.count - 1]

        // Complexity: O(m) for segment size m in this recursion node.
        func recurse(_ left: Int, _ right: Int) {
            if right - left <= 1 { return }

            let xa = anchors[left].x
            let ya = anchors[left].y
            let xb = anchors[right].x
            let yb = anchors[right].y
            if xb <= xa { return }

            var bestIndex: Int?
            var bestWeightedResidual = -Double.infinity
            var bestRawResidual = 0.0

            for k in (left + 1)..<right {
                let x = anchors[k].x
                let y = anchors[k].y
                let yHat = ya + (yb - ya) * ((x - xa) / (xb - xa))
                let rawResidual = abs(y - yHat)
                let weightedResidual = anchors[k].weight * rawResidual
                if weightedResidual > bestWeightedResidual {
                    bestWeightedResidual = weightedResidual
                    bestRawResidual = rawResidual
                    bestIndex = k
                }
            }

            if let bestIndex, bestRawResidual > tauFit {
                knots.insert(bestIndex)
                recurse(left, bestIndex)
                recurse(bestIndex, right)
            }
        }

        recurse(0, anchors.count - 1)

        let sortedKnots = knots.sorted()
        var xs: [Double] = []
        var ys: [Double] = []
        xs.reserveCapacity(sortedKnots.count)
        ys.reserveCapacity(sortedKnots.count)

        for index in sortedKnots {
            xs.append(anchors[index].x)
            ys.append(anchors[index].y)
        }

        var monotoneX: [Double] = []
        var monotoneY: [Double] = []
        monotoneX.reserveCapacity(xs.count)
        monotoneY.reserveCapacity(ys.count)

        monotoneX.append(xs[0])
        monotoneY.append(ys[0])

        for i in 1..<xs.count {
            let x = xs[i]
            var y = ys[i]

            if x <= monotoneX[monotoneX.count - 1] + 1e-9 {
                continue
            }
            if y <= monotoneY[monotoneY.count - 1] + 1e-9 {
                y = monotoneY[monotoneY.count - 1] + 1e-6
            }

            monotoneX.append(x)
            monotoneY.append(y)
        }

        guard !monotoneX.isEmpty else { return nil }
        let slope = monotoneX.count >= 2
            ? (monotoneY[1] - monotoneY[0]) / Swift.max(monotoneX[1] - monotoneX[0], 1e-9)
            : 1

        return TimeWarpMapping(xs: monotoneX, ys: monotoneY, fallbackSlope: slope)
    }

    /// - Complexity: O(1).
    static func endpointLinearFallback(lhs: [OnsetEvent], rhs: [OnsetEvent]) -> TimeWarpMapping {
        guard let x0 = lhs.first?.time,
              let x1 = lhs.last?.time,
              let y0 = rhs.first?.time,
              let y1 = rhs.last?.time
        else {
            return .identity
        }

        if abs(x1 - x0) < 1e-9 {
            return TimeWarpMapping(xs: [x0], ys: [y0], fallbackSlope: 1)
        }

        let slope = (y1 - y0) / (x1 - x0)
        return TimeWarpMapping(xs: [x0, x1], ys: [y0, y1], fallbackSlope: slope)
    }

    /// - Complexity: O(n log n), where n is the number of onset events.
    static func q10IOI(from events: [OnsetEvent]) -> Double? {
        guard events.count >= 2 else { return nil }

        var uniqueTimes: [Double] = []
        uniqueTimes.reserveCapacity(events.count)
        for event in events {
            if let last = uniqueTimes.last, abs(event.time - last) < 1e-6 {
                continue
            }
            uniqueTimes.append(event.time)
        }

        guard uniqueTimes.count >= 2 else { return nil }

        var intervals: [Double] = []
        intervals.reserveCapacity(uniqueTimes.count - 1)
        for i in 1..<uniqueTimes.count {
            let diff = uniqueTimes[i] - uniqueTimes[i - 1]
            if diff > 1e-9 {
                intervals.append(diff)
            }
        }

        guard !intervals.isEmpty else { return nil }
        intervals.sort()

        if intervals.count == 1 {
            return intervals[0]
        }

        let position = 0.1 * Double(intervals.count - 1)
        let low = Int(position.rounded(.down))
        let high = Int(position.rounded(.up))
        if low == high {
            return intervals[low]
        }

        let t = position - Double(low)
        return intervals[low] + t * (intervals[high] - intervals[low])
    }

    /// - Complexity: O(n log n), where n is the number of values.
    static func mad(_ values: [Double]) -> Double? {
        guard !values.isEmpty, let median = values.median else { return nil }
        return values.map { abs($0 - median) }.median
    }

    /// - Complexity: O(1).
    static func huber(_ z: Double, delta: Double) -> Double {
        let value = abs(z)
        if value <= delta {
            return 0.5 * value * value
        }
        return delta * (value - 0.5 * delta)
    }

    /// - Complexity: O(k log k), where k is the number of anchors.
    static func estimatedFitTolerance(_ anchors: [Anchor]) -> Double {
        guard anchors.count >= 3 else { return 0.08 }

        let first = anchors[0]
        let last = anchors[anchors.count - 1]
        let dx = Swift.max(last.x - first.x, 1e-9)

        var residuals: [Double] = []
        residuals.reserveCapacity(anchors.count - 2)
        for anchor in anchors[1..<(anchors.count - 1)] {
            let yHat = first.y + (last.y - first.y) * ((anchor.x - first.x) / dx)
            residuals.append(abs(anchor.y - yHat))
        }

        if let residualMAD = mad(residuals) {
            return Swift.max(0.08, 2.5 * residualMAD)
        }
        return 0.08
    }
}
