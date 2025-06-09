//
//  Notes + ref len.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import Foundation
import Accelerate


extension MIDINotes {
    
    /// Calculates the length of the reference note in beats.
    ///
    /// A reference note is defined as the baseline most commonly occurred note. This could be, for example, 16th note.
    ///
    /// In proper midi, notes should have onsets at *m* \* 1/2^*n*.
    ///
    /// ```swift
    /// // start by normalizing tempo
    /// let referenceNoteLength = container.tracks[0].notes.deriveReferenceNoteLength()
    ///
    /// let tempo = 120 * 1/4 / referenceNoteLength
    /// container.applyTempo(tempo: tempo)
    /// ```
    ///
    /// - Parameters:
    ///   - minimumNoteDistance: Drop notes whose distances from previous notes are less than `minimumNoteDistance`. As these notes could be forming a chord. Defaults to 2^-4, 64th note.
    ///
    /// - Complexity: O(*n* log *n*). Loss function within golden ratio search.
    ///
    /// - Returns: The length of reference note in beats. In 120 bpm, 4/4, which is MIDI default, the new bpm is then 120 \* 0.25 / return value.
    public func deriveReferenceNoteLength(
        minimumNoteDistance: Double = Double(sign: .plus, exponent: -4, significand: 1)
    ) -> Double {
        let distances = [Double](unsafeUninitializedCapacity: self.contents.count - 1) { buffer, initializedCount in
            initializedCount = 0
            
            var i = 1
            while i < self.contents.count {
                let distance = self.contents[i].onset - self.contents[i-1].onset
                if distance >= minimumNoteDistance {
                    buffer[initializedCount] = distance
                    initializedCount &+= 1
                }
                
                i &+= 1
            }
        }
        
        /// - Complexity: O(*n*).
        func loss(distances: [Double], reference: Double) -> Double {
            var i = 1
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
        
        return goldenSectionSearch(left: 0, right: vDSP.mean(distances) * 3 / 2) {
            loss(distances: distances, reference: $0)
        }
    }
    
}
