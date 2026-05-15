//
//  Bar Barriers.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-17.
//

import Foundation
import Accelerate


extension IndexedContainer {
    
    public struct LocalBarRegion: Sendable, Hashable {
        
        /// Region start time in IndexedContainer beat-space.
        public let onset: Double
        
        /// Representative local bar length in beats.
        public let barLength: Double
        
        /// Region span in beats.
        public let duration: Double
        
        /// Confidence in [0, 1]. Higher means more internally consistent local periodicity.
        public let confidence: Double
        
        @inlinable
        public init(onset: Double, barLength: Double, duration: Double, confidence: Double) {
            self.onset = onset
            self.barLength = barLength
            self.duration = duration
            self.confidence = confidence
        }
        
    }

    private struct CanonicalMetricEvent {
        let onset: Double
        let effectiveOffset: Double
        let effectiveDuration: Double
        let weight: Double
    }

    private struct WindowEstimate {
        let start: Double
        let end: Double
        let barLength: Double
        let confidence: Double
    }

    /// Sustain durations adjusted to span the entire container.
    public func sustainDurations() -> [Double] {
        var results: [Double] = []
        results.reserveCapacity(self.sustains.count)
        var lastOffset = 0.0
        for sustain in self.sustains {
            results.append(sustain.offset - lastOffset)
            lastOffset = sustain.offset
        }
        return results
    }

    /// Estimates the baseline bar (measure) length in beats from human-recorded MIDI notes.
    ///
    /// A measure should divide-or be divisible by-the majority of observed note and sustain
    /// lengths. We therefore search for the bar length that minimises a weighted loss where
    /// longer sustains influence the fit more than short attack-only notes.
    ///
    /// - Parameters: none
    /// - Returns: The estimated measure length in beats.
    /// - Complexity: O(*n* · *m*), where *m* is the capped number of descent iterations.
    public func baselineBarLength(beatsPerMeasure: Double = 4) -> Double {
        let sustainWeight = 2.5
        return IndexedContainer.baselineBarLength(beatsPerMeasure: beatsPerMeasure, samples: self.sustainDurations().map { ($0, sustainWeight) } + self.contents.map { ($0.duration, 1.0) })
    }

    /// Estimates the baseline bar (measure) length in beats from human-recorded MIDI notes.
    ///
    /// A measure should divide-or be divisible by-the majority of observed note and sustain
    /// lengths. We therefore search for the bar length that minimises a weighted loss where
    /// longer sustains influence the fit more than short attack-only notes.
    ///
    /// - Parameters: none
    /// - Returns: The estimated measure length in beats.
    /// - Complexity: O(*n* · *m*), where *m* is the capped number of descent iterations.
    public static func baselineBarLength(beatsPerMeasure: Double = 4, samples: [(duration: Double, weight: Double)]) -> Double {

        /// Fall back early when no timing information exists.
        let durations = samples.map { $0.duration }
        guard let median = durations.median, median > 0 else { return 0 }

        /// - Complexity: O(*n*).
        func loss(samples: [(duration: Double, weight: Double)], reference: Double) -> Double {
            guard reference > 0 else { return .infinity }
            var i = 0
            var loss: Double = 0
            while i < samples.count {
                let sample = samples[i]
                let duration = sample.duration
                let weight = sample.weight
                if duration > 0 {
                    // Measure how closely the ratio between duration and reference aligns to
                    // integer multiples, regardless of which term is larger.
                    let ratio: Double
                    if duration >= reference {
                        ratio = duration / reference
                    } else {
                        ratio = reference / duration
                    }
                    let base = duration
                    let nearest = Swift.max(1.0, ratio.rounded())
                    let deviation = abs(ratio - nearest)
                    loss += deviation * base * weight
                }
                i &+= 1
            }

            return loss
        }

        /// Performs a derivative-free descent anchored at `center` to favour nearby minima.
        func localMinimumAroundCenter(around center: Double, left: Double, right: Double, tolerance: Double = 1e-4, body: (Double) -> Double) -> Double {
            guard right > left else { return center }
            var current = Swift.min(Swift.max(center, left), right)
            var currentLoss = body(current)
            if !currentLoss.isFinite {
                return center
            }
            var step = (right - left) / 4
            let minStep = tolerance
            while step > minStep {
                let leftCandidate = Swift.max(left, current - step)
                let rightCandidate = Swift.min(right, current + step)
                var moved = false
                var bestPoint = current
                var bestLoss = currentLoss
                let leftLoss = body(leftCandidate)
                if leftLoss < bestLoss {
                    bestPoint = leftCandidate
                    bestLoss = leftLoss
                    moved = true
                }
                let rightLoss = body(rightCandidate)
                if rightLoss < bestLoss {
                    bestPoint = rightCandidate
                    bestLoss = rightLoss
                    moved = true
                }
                if moved {
                    current = bestPoint
                    currentLoss = bestLoss
                } else {
                    step /= 2
                }
            }
            return current
        }

        let left = beatsPerMeasure / 2
        let right = beatsPerMeasure * 1.5
        let objective: (Double) -> Double = { loss(samples: samples, reference: $0) }
        let fit = localMinimumAroundCenter(around: beatsPerMeasure, left: left, right: right, body: objective)

        return fit.isFinite ? fit : median
    }

    /// Segments the timeline into local regions with piecewise bar-length estimates.
    ///
    /// `IndexedContainer` uses normalized 120-BPM beat-space, so time-based inputs are in beats.
    ///
    /// - Parameters:
    ///   - beatsPerMeasure: Prior bar-length center (in beats).
    ///   - windowDuration: Sliding window duration in beats.
    ///   - overlapRatio: Window overlap ratio in `[0, 0.95]`.
    ///   - barTolerance: Relative merge tolerance between adjacent windows.
    ///   - minRegionDuration: Minimum segment duration in beats.
    /// - Returns: Local bar regions sorted by onset.
    @available(*, deprecated, message: "Don't use, inaccurate.")
    public func localBarRegions(
        beatsPerMeasure: Double = 4,
        windowDuration: Double = 8,
        overlapRatio: Double = 0.5,
        barTolerance: Double = 0.15,
        minRegionDuration: Double = 2
    ) -> [LocalBarRegion] {
        let events = self.canonicalMetricEvents()
        guard !events.isEmpty else { return [] }

        let globalBarLength = self.baselineBarLength(beatsPerMeasure: beatsPerMeasure)
        guard globalBarLength.isFinite, globalBarLength > 1e-6 else { return [] }

        let safeWindowDuration = Swift.max(windowDuration, globalBarLength * 0.75)
        let safeOverlap = clamp(overlapRatio, min: 0, max: 0.95)
        let step = Swift.max(0.25, safeWindowDuration * (1 - safeOverlap))
        let lowerSearchBound = Swift.max(1.5, Swift.min(globalBarLength, beatsPerMeasure) * 0.7)
        let upperSearchBound = Swift.max(globalBarLength, beatsPerMeasure) * 1.35
        let searchRange = (lowerSearchBound, upperSearchBound)
        guard let timelineStart = events.first?.onset else { return [] }

        var timelineEnd = timelineStart
        for event in events {
            timelineEnd = Swift.max(timelineEnd, event.effectiveOffset)
        }
        guard timelineEnd > timelineStart else {
            return [LocalBarRegion(onset: timelineStart, barLength: globalBarLength, duration: globalBarLength, confidence: 0.2)]
        }

        var estimates: [WindowEstimate] = []
        var cursor = timelineStart
        while cursor < timelineEnd {
            let end = Swift.min(timelineEnd, cursor + safeWindowDuration)
            let localEvents = events.filter { $0.onset >= cursor && $0.onset < end }

            if localEvents.count >= 4,
               let local = Self.estimateLocalBarLength(
                events: localEvents,
                windowStart: cursor,
                globalBarLength: globalBarLength,
                searchRange: searchRange
               ) {
                estimates.append(
                    WindowEstimate(start: cursor, end: end, barLength: local.barLength, confidence: local.confidence)
                )
            }

            if end >= timelineEnd {
                break
            }
            cursor += step
        }

        if estimates.isEmpty {
            return [
                LocalBarRegion(onset: timelineStart, barLength: globalBarLength, duration: timelineEnd - timelineStart, confidence: 0.25)
            ]
        }

        let stabilized = Self.stabilizeWindowEstimates(estimates)
        let merged = Self.mergeWindowEstimates(stabilized, tolerance: Swift.max(barTolerance, 0.18))
        let condensed = Self.absorbShortRegions(merged, minRegionDuration: minRegionDuration)
        return condensed.map { estimate in
            let duration = estimate.end - estimate.start
            return LocalBarRegion(
                onset: estimate.start,
                barLength: estimate.barLength,
                duration: duration,
                confidence: clamp(estimate.confidence, min: 0, max: 1)
            )
        }
    }

}


private extension IndexedContainer {

    private func canonicalMetricEvents() -> [CanonicalMetricEvent] {
        guard !self.contents.isEmpty else { return [] }

        var events: [CanonicalMetricEvent] = []
        events.reserveCapacity(self.contents.count + self.sustains.count)

        for note in self.contents {
            let onset = Self.quantize(note.onset, step: 1e-3)
            let effectiveOffset = Self.soundingOffset(of: note, sustains: self.sustains)
            let duration = Swift.max(1e-4, effectiveOffset - onset)
            let normalizedVelocity = clamp(Double(note.velocity) / 127.0, min: 0.0, max: 1.0)
            let attackWeight = 0.4 + normalizedVelocity
            let articulationWeight = 1 / sqrt(Swift.max(duration, 0.125))
            let weight = attackWeight * articulationWeight
            events.append(
                CanonicalMetricEvent(
                    onset: onset,
                    effectiveOffset: effectiveOffset,
                    effectiveDuration: duration,
                    weight: weight
                )
            )
        }

        for sustain in self.sustains {
            let onset = Self.quantize(sustain.onset, step: 1e-3)
            let duration = Swift.max(1e-4, sustain.duration)
            events.append(
                CanonicalMetricEvent(
                    onset: onset,
                    effectiveOffset: sustain.offset,
                    effectiveDuration: duration,
                    weight: 1.4
                )
            )
        }

        return events.sorted { $0.onset < $1.onset }
    }

    static func soundingOffset(of note: MIDINote, sustains: MIDISustainEvents) -> Double {
        let physical = note.offset

        if let sustainIndex = sustains.index(at: physical) {
            return Swift.max(physical, sustains[sustainIndex].offset)
        }

        guard let previousIndex = sustains.lastIndex(before: physical) else {
            return physical
        }

        let previous = sustains[previousIndex]
        let next = sustains.first(after: physical)
        if previous.offset >= physical - 1 / 32,
           next.map({ $0.onset - previous.offset <= 1 / 16 }) ?? false {
            return Swift.max(physical, previous.offset)
        }

        return physical
    }

    private static func estimateLocalBarLength(
        events: [CanonicalMetricEvent],
        windowStart: Double,
        globalBarLength: Double,
        searchRange: (Double, Double)
    ) -> (barLength: Double, confidence: Double)? {
        guard !events.isEmpty else { return nil }

        let durationSamples = events.map { ($0.effectiveDuration, $0.weight) }
        let baseline = IndexedContainer.baselineBarLength(
            beatsPerMeasure: globalBarLength,
            samples: durationSamples
        )

        var candidates: [Double] = [baseline, globalBarLength]
        let lower = Swift.max(1e-3, searchRange.0)
        let upper = Swift.max(lower + 1e-3, searchRange.1)
        let candidateStride = Swift.max(0.02, (upper - lower) / 36)
        var candidate = lower
        while candidate <= upper {
            candidates.append(candidate)
            candidate += candidateStride
        }

        candidates = Array(Set(candidates.filter { $0.isFinite && $0 > 1e-3 })).sorted()
        guard !candidates.isEmpty else { return nil }

        let onsets = events.map(\.onset)
        let weights = events.map(\.weight)
        let totalWeight = Swift.max(1e-8, vDSP.sum(weights))

        let sortedWeights = weights.sorted()
        let strongWeightIndex = Int(Double(sortedWeights.count - 1) * 0.9)
        let strongWeightThreshold = sortedWeights[strongWeightIndex]

        var strongOnsets: [Double] = []
        var strongWeights: [Double] = []
        strongOnsets.reserveCapacity(events.count)
        strongWeights.reserveCapacity(events.count)
        for i in events.indices where weights[i] >= strongWeightThreshold {
            strongOnsets.append(onsets[i])
            strongWeights.append(weights[i])
        }

        if strongOnsets.count < 3 {
            strongOnsets = onsets
            strongWeights = weights
        }

        var bestCandidate = globalBarLength
        var bestCost = Double.infinity
        var secondBestCost = Double.infinity

        for candidate in candidates {
            let cost = localFitCost(
                candidate: candidate,
                windowStart: windowStart,
                globalBarLength: globalBarLength,
                strongOnsets: strongOnsets,
                strongWeights: strongWeights,
                events: events
            )
            if cost < bestCost {
                secondBestCost = bestCost
                bestCost = cost
                bestCandidate = candidate
            } else if cost < secondBestCost {
                secondBestCost = cost
            }
        }

        let normalizedCost = bestCost / totalWeight
        let separation = (secondBestCost - bestCost) / Swift.max(totalWeight, 1e-8)
        let confidence = clamp(1 / (1 + normalizedCost) + 0.3 * clamp(separation, min: 0, max: 1), min: 0, max: 1)
        return (bestCandidate, confidence)
    }

    private static func localFitCost(
        candidate: Double,
        windowStart: Double,
        globalBarLength: Double,
        strongOnsets: [Double],
        strongWeights: [Double],
        events: [CanonicalMetricEvent]
    ) -> Double {
        guard candidate > 1e-6 else { return .infinity }

        var phasePenalty = 0.0
        for i in strongOnsets.indices {
            let phase = ((strongOnsets[i] - windowStart) / candidate).truncatingRemainder(dividingBy: 1)
            let wrapped = phase < 0 ? phase + 1 : phase
            let distance = Swift.min(wrapped, 1 - wrapped)
            phasePenalty += strongWeights[i] * (1 - exp(-5.5 * distance))
        }

        var ioiPenalty = 0.0
        if strongOnsets.count >= 2 {
            for i in 1..<strongOnsets.count {
                let ioi = strongOnsets[i] - strongOnsets[i - 1]
                if ioi <= 1e-5 { continue }
                let ratio = ioi >= candidate ? ioi / candidate : candidate / ioi
                let nearest = Swift.max(1.0, ratio.rounded())
                let deviation = abs(ratio - nearest)
                let edgeWeight = 0.5 * (strongWeights[i] + strongWeights[i - 1])
                ioiPenalty += deviation * edgeWeight
            }
        } else if events.count >= 2 {
            for i in 1..<events.count {
                let ioi = events[i].onset - events[i - 1].onset
                if ioi <= 1e-5 { continue }
                let ratio = ioi >= candidate ? ioi / candidate : candidate / ioi
                let nearest = Swift.max(1.0, ratio.rounded())
                let deviation = abs(ratio - nearest)
                let edgeWeight = 0.5 * (events[i].weight + events[i - 1].weight)
                ioiPenalty += deviation * edgeWeight
            }
        }

        let priorPenalty = abs(candidate - globalBarLength) / Swift.max(globalBarLength, 1e-6)
        return phasePenalty * 0.75 + ioiPenalty * 0.25 + priorPenalty * 0.5
    }

    private static func mergeWindowEstimates(_ estimates: [WindowEstimate], tolerance: Double) -> [WindowEstimate] {
        guard let first = estimates.first else { return [] }
        var merged: [WindowEstimate] = [first]

        for estimate in estimates.dropFirst() {
            guard var last = merged.last else { continue }
            let baseline = Swift.max(Swift.max(last.barLength, estimate.barLength), 1e-6)
            let relativeDifference = abs(estimate.barLength - last.barLength) / baseline
            if relativeDifference <= tolerance {
                let leftDuration = Swift.max(1e-6, last.end - last.start)
                let rightDuration = Swift.max(1e-6, estimate.end - estimate.start)
                let leftWeight = leftDuration * Swift.max(0.05, last.confidence)
                let rightWeight = rightDuration * Swift.max(0.05, estimate.confidence)
                let totalWeight = leftWeight + rightWeight
                let fusedBarLength = (last.barLength * leftWeight + estimate.barLength * rightWeight) / totalWeight
                let fusedConfidence = (last.confidence * leftWeight + estimate.confidence * rightWeight) / totalWeight
                last = WindowEstimate(
                    start: last.start,
                    end: Swift.max(last.end, estimate.end),
                    barLength: fusedBarLength,
                    confidence: fusedConfidence
                )
                merged[merged.count - 1] = last
            } else {
                merged.append(estimate)
            }
        }

        return merged
    }

    private static func stabilizeWindowEstimates(_ estimates: [WindowEstimate]) -> [WindowEstimate] {
        guard estimates.count >= 3 else { return estimates }

        var smoothed = estimates
        for i in 1..<(estimates.count - 1) {
            let left = estimates[i - 1]
            let center = estimates[i]
            let right = estimates[i + 1]

            let leftWeight = Swift.max(0.05, left.confidence)
            let centerWeight = Swift.max(0.05, center.confidence) * 1.4
            let rightWeight = Swift.max(0.05, right.confidence)
            let totalWeight = leftWeight + centerWeight + rightWeight
            let barLength = (left.barLength * leftWeight + center.barLength * centerWeight + right.barLength * rightWeight) / totalWeight

            smoothed[i] = WindowEstimate(
                start: center.start,
                end: center.end,
                barLength: barLength,
                confidence: center.confidence
            )
        }

        return smoothed
    }

    private static func absorbShortRegions(_ estimates: [WindowEstimate], minRegionDuration: Double) -> [WindowEstimate] {
        guard !estimates.isEmpty else { return [] }
        var regions = estimates

        while regions.count > 1 {
            guard let shortIndex = regions.firstIndex(where: { $0.end - $0.start < minRegionDuration }) else {
                break
            }

            if shortIndex == 0 {
                let first = regions.removeFirst()
                let next = regions[0]
                regions[0] = WindowEstimate(
                    start: first.start,
                    end: next.end,
                    barLength: next.barLength,
                    confidence: (first.confidence + next.confidence) / 2
                )
            } else if shortIndex == regions.count - 1 {
                let last = regions.removeLast()
                let previousIndex = regions.count - 1
                let previous = regions[previousIndex]
                regions[previousIndex] = WindowEstimate(
                    start: previous.start,
                    end: last.end,
                    barLength: previous.barLength,
                    confidence: (previous.confidence + last.confidence) / 2
                )
            } else {
                let previous = regions[shortIndex - 1]
                let current = regions[shortIndex]
                let next = regions[shortIndex + 1]
                let joinLeft = abs(current.barLength - previous.barLength)
                let joinRight = abs(current.barLength - next.barLength)

                if joinLeft <= joinRight {
                    regions[shortIndex - 1] = WindowEstimate(
                        start: previous.start,
                        end: current.end,
                        barLength: (previous.barLength + current.barLength) / 2,
                        confidence: (previous.confidence + current.confidence) / 2
                    )
                    regions.remove(at: shortIndex)
                } else {
                    regions[shortIndex + 1] = WindowEstimate(
                        start: current.start,
                        end: next.end,
                        barLength: (current.barLength + next.barLength) / 2,
                        confidence: (current.confidence + next.confidence) / 2
                    )
                    regions.remove(at: shortIndex)
                }
            }
        }

        return regions
    }

    private static func quantize(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

}


public extension Collection where Index == Int, Element: BinaryFloatingPoint {

    @inlinable
    var median: Element? {
        guard !self.isEmpty else { return nil }
        let sorted = self.sorted()
        let mid = self.count / 2
        if self.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }

}


private func clamp(_ value: Double, min: Double, max: Double) -> Double {
    Swift.min(Swift.max(value, min), max)
}
