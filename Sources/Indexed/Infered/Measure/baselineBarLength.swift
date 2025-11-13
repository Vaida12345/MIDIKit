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
        self.sustains.reduce(into: []) { partialResult, sustain in
            partialResult.append(sustain.offset - (partialResult.last ?? 0))
        }
    }
    
    /// Estimates the baseline bar (measure) length in beats from human-recorded MIDI notes.
    ///
    /// A measure should divide—or be divisible by—the majority of observed note and sustain
    /// lengths. We therefore search for the bar length that minimises a weighted loss where
    /// longer sustains influence the fit more than short attack-only notes.
    ///
    /// - Parameters: none
    /// - Returns: The estimated measure length in beats.
    /// - Complexity: O(*n* log *n*) due to the golden-section search invoking a linear loss.
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
    /// - Complexity: O(*n* log *n*) due to the golden-section search invoking a linear loss.
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
                    let base: Double
                    if duration >= reference {
                        ratio = duration / reference
                        base = reference
                    } else {
                        ratio = reference / duration
                        base = duration
                    }
                    let nearest = Swift.max(1.0, ratio.rounded())
                    let deviation = abs(ratio - nearest)
                    loss += deviation * base * weight
                }
                i &+= 1
            }
            
            return loss
        }
        
        /// - Complexity: O(*n* log *n*).
        func goldenSectionSearch(left: Double, right: Double, tolerance: Double = 1e-5, body: (Double) -> Double) -> Double {
            let gr = (sqrt(5) + 1) / 2 // Golden ratio constant
            
            var a = left
            var b = right
            
            // We are looking for the minimum, so we apply the golden section search logic
            var c = b - (b - a) / gr
            var d = a + (b - a) / gr
            
            while abs(c - d) > tolerance {
                if body(c) < body(d) {
                    b = d
                } else {
                    a = c
                }
                
                c = b - (b - a) / gr
                d = a + (b - a) / gr
            }
            
            // The point of minimum loss is between a and b
            return (b + a) / 2
        }
        
        let left = beatsPerMeasure / 2
        let right = beatsPerMeasure * 1.5
        
        let fit = goldenSectionSearch(left: left, right: right) {
            loss(samples: samples, reference: $0)
        }
        
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
