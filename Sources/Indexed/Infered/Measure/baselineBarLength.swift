//
//  Bar Barriers.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-17.
//

import Foundation


extension IndexedContainer {
    
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
    /// A measure should divide—or be divisible by—the majority of observed note and sustain
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
    /// A measure should divide—or be divisible by—the majority of observed note and sustain
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
