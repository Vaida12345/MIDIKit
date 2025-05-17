//
//  Bar Barriers.swift
//  MIDIKit
//
//  Created by Vaida on 2025-05-17.
//

import Foundation
import Accelerate


extension IndexedContainer {
    
    /// Calculates the length of the reference note in beats.
    ///
    /// A reference note is defined as the baseline most commonly occurred note. This could be, for example, 16th note.
    ///
    /// In proper midi, notes should have onsets at *m* \* 1/2^*n*.
    /// - Parameters:
    ///   - minimumNoteDistance: Drop notes whose distances from previous notes are less than `minimumNoteDistance`. As these notes could be forming a chord. Defaults to 2^-4, 64th note.
    ///
    /// - Complexity: O(*n* log *n*). Loss function within golden ratio search.
    ///
    /// - Returns: The length of reference note in beats.
    public func baselineBarLength(
        minimumNoteDistance: Double = Double(sign: .plus, exponent: -4, significand: 1)
    ) -> Double {
        let durations = self.sustains.map(\.duration)
        
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
        
        let median = durations.median ?? 0
        let variance: Double = max(1/6, median * 0.5)
        
        print("Sustain median is \(median)")
        
        return goldenSectionSearch(left: median - variance, right: median + variance) {
            loss(distances: durations, reference: $0)
        }
    }
    
    public func downbeats() -> [MIDINote] {
        guard !self.isEmpty else { return [] }
        let _chords = Chord.makeChords(from: self)
        let baselineBarLength = self.baselineBarLength()
        
        var beat = baselineBarLength
        var downbeats: [MIDINote] = [self.contents.first!]
        let endBeat = self.contents.last!.offset
        downbeats.reserveCapacity(Int(endBeat / baselineBarLength))
        
        let _bases = _chords.map { $0.min(by: { $0.note < $1.note })! }
        
        var firstChordIndex = 0
        var _lastChordIndex = _chords.firstIndex(after: beat + baselineBarLength)
        
        while let lastChordIndex = _lastChordIndex {
            print("context: \(_chords[firstChordIndex].leadingOnset) ..< \(_chords[lastChordIndex].leadingOnset) | \(beat)")
            
            guard firstChordIndex < lastChordIndex else {
                beat += baselineBarLength
                _lastChordIndex = _chords.firstIndex(after: beat + baselineBarLength)
                // downbeat not found, move on
                continue
            }
            
            let chords = _chords[firstChordIndex ..< lastChordIndex]
            let bases = _bases[firstChordIndex ..< lastChordIndex]
            var weights = [Double](repeating: 0, count: chords.count)
            
            // distance-based
            for (i, base) in bases.enumerated() {
                weights[i] += normalPDF(x: base.onset, mean: beat, stdDev: baselineBarLength / 2) / 0.4 * 2
            }
            
            // pointy-end
            var pointyCount = [Double](repeating: 0, count: chords.count)
//            let lowerBase = bases.min(of: \.note)!
//            let highBase = bases.max(of: \.note)!
//            let baseSpan = Double(highBase - lowerBase)
            for i in 0..<bases.count {
                // explore left
                var left = i + firstChordIndex - 1
                while left >= max(firstChordIndex - chords.count, 0) { // lower limit
                    guard _bases[left].note > _bases[i + firstChordIndex].note else { break }
                    left -= 1
                }
                pointyCount[i] += Double(i + firstChordIndex - left)/* * Double(highBase - _bases[i + firstChordIndex].note) / baseSpan*/
            }
            print(bases.map { $0.onset.formatted(.number.precision(.integerAndFractionLength(integer: 3, fraction: 2))) }.joined(separator: "  "))
            print(pointyCount.map { $0.formatted(.number.precision(.integerAndFractionLength(integer: 3, fraction: 2))) }.joined(separator: "  "))
            
            let pointyCountMax = pointyCount.max()!
            for i in 0..<bases.count {
                weights[i] += pointyCountMax == 0 ? 0 : (pointyCount[i] / pointyCountMax)
            }
            print(weights.map { $0.formatted(.number.precision(.integerAndFractionLength(integer: 3, fraction: 2))) }.joined(separator: "  "))
            
            // change in base
            
            // next
            let maxIndex = weights.maxIndex(of: \.self)!
            downbeats.append(bases[bases.startIndex + maxIndex].pointee)
            print("=> \(bases[bases.startIndex + maxIndex].pointee.onset)\n")
            firstChordIndex += maxIndex + 1
            beat = bases[bases.startIndex + maxIndex].pointee.onset + baselineBarLength
            _lastChordIndex = _chords.firstIndex(after: beat + baselineBarLength)
        }
        
        return downbeats
    }
    
}


public extension Collection where Index == Int, Element: BinaryFloatingPoint {
    
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


func normalPDF(x: Double, mean: Double = 0, stdDev: Double = 1) -> Double {
    let exponent = -pow(x - mean, 2) / (2 * pow(stdDev, 2))
    return (1.0 / (stdDev * sqrt(2 * .pi))) * exp(exponent)
}
