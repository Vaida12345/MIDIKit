//
//  Bar Barriers.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-17.
//

import Foundation
import Accelerate


extension IndexedContainer {
    
    /// Calculates the length of the reference note in beats, based on sustain & notes.
    ///
    /// A reference note is defined as the baseline most commonly occurred note. This could be, for example, 16th note.
    ///
    /// In proper scores, notes should have onsets at *m* \* 1/2^*n*.
    ///
    /// - Complexity: O(*n* log *n*). Loss function within golden ratio search.
    ///
    /// - Returns: The length of reference note in beats.
    public func baselineBarLength() -> Double {
        let durations = self.sustains.map(\.duration) + self.contents.map(\.duration)
        
        /// - Complexity: O(*n*).
        func loss(distances: [Double], reference: Double) -> Double {
            var i = 0
            var loss: Double = 0
            while i < distances.count {
                let remainder = distances[i].truncatingRemainder(dividingBy: reference)
                assert(remainder >= 0)
                loss += Swift.min(remainder, Swift.max(reference - remainder, 0))
                
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
        
        var median = durations.median ?? 0
        let variance: Double = median / 2
        
        if median < 3 {
            median *= 2
        }
        
        let fit = goldenSectionSearch(left: median - variance, right: median + variance * 3) {
            loss(distances: durations, reference: $0)
        }
        if abs(median - variance - fit) < 0.1 {
            // no pattern found
            return median
        } else {
            return fit
        }
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
