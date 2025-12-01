//
//  Downbeat.swift
//  MIDIKit
//
//  Created by Vaida on 2025-11-13.
//

import Foundation


extension IndexedContainer {
    
    /// Calculates the start of each measure in beats.
    ///
    /// This function relies on sustains to calculate downbeats.
    ///
    /// - Note: inaccurate.
    ///
    /// - Parameters:
    ///   - beatsPerMeasure: Number of beats in a measure. This value is ignored if prior is specified.
    ///   - prior: If you already know the first few measures are like, pass to inform inference.
    public func downbeats(
        beatsPerMeasure: Double = 4,
        prior: [Double]? = nil
    ) -> [Double] {
        var downbeats: [Double]
        let idealMeasureWidth: Double
        var onset: Double
        var lastCheckedSustainIndex = 0
        
        if let prior, prior.count > 1 {
            downbeats = prior
            let beatsPerMeasure = downbeats.gaps()
            idealMeasureWidth = self.baselineBarLength(beatsPerMeasure: beatsPerMeasure.mean!)
            onset = prior.last!
            if let sustainIndexAfter = self.sustains.firstIndex(after: onset), sustainIndexAfter > 1 {
                lastCheckedSustainIndex = sustainIndexAfter - 1
            }
        } else {
            downbeats = [0]
            idealMeasureWidth = self.baselineBarLength(beatsPerMeasure: beatsPerMeasure)
            onset = 0
        }
        
        let chords = self.chords()
        
        guard let maxOffset = self.contents.max(of: \.offset) else { return [] } // self is empty
        while onset < maxOffset {
            // determine offset
            var idealOffset = onset + idealMeasureWidth
            
            // 1, check nearby measures
            var sustainCandidates: [Double] = []
            if let sustainIndexAfter = self.sustains.firstIndex(after: idealOffset) {
                if sustainIndexAfter > lastCheckedSustainIndex {
                    sustainCandidates.append(self.sustains[sustainIndexAfter].onset)
                }
                
                if sustainIndexAfter - 1 > lastCheckedSustainIndex {
                    sustainCandidates.append(self.sustains[sustainIndexAfter - 1].onset)
                }
            }
            // use sustain to reshape ideal offset
            sustainCandidates = sustainCandidates.sorted { abs($0 - idealOffset) < abs($1 - idealOffset) }
            if let sustain = sustainCandidates.first, abs(sustain - idealOffset) < idealMeasureWidth / 4 {
                idealOffset = sustain
            }
            
            // 2, snap to nearby onset
            guard let nextChordIndex = chords.firstIndex(after: idealOffset) else {
                // maybe crossed the end?
                downbeats.append(idealOffset)
                onset = idealOffset
                break
            }
            
            guard nextChordIndex > 0 else {
                downbeats.append(chords[nextChordIndex].leadingOnset)
                onset = chords[nextChordIndex].leadingOnset
                continue
            }
            
            // snap to nearest chord
            let next = chords[nextChordIndex]
            let prev = chords[nextChordIndex - 1]
            
            let nextDistance = abs(next.leadingOnset - idealOffset)
            let prevDistance = abs(prev.leadingOnset - idealOffset)
            
            if nextDistance + 0.25 > prevDistance, prev.leadingOnset > onset { // 16th note
                // next distance just win by a tiny amount, use prev
                idealOffset = prev.leadingOnset
            } else {
                idealOffset = next.leadingOnset
            }
            
            assert(idealOffset > onset)
            
            downbeats.append(idealOffset)
            onset = idealOffset
        }
        
        return downbeats
    }
    
}


extension Sequence {
    
    func iterate(
        _ body: (_ curr: Element, _ next: Element?) -> Void
    ) {
        var iterator = self.makeIterator()
        var _curr = iterator.next()
        var next = iterator.next()
        
        while let curr = _curr {
            body(curr, next)
            _curr = next
            next = iterator.next()
        }
    }
    
}


extension Array<Double> {
    
    func gaps() -> [Double] {
        let sorted = self.sorted()
        guard sorted.count > 1 else { return [] }
        var gaps: [Double] = []
        gaps.reserveCapacity(sorted.count - 1)
        
        sorted.iterate { curr, next in
            if let next = next {
                gaps.append(next - curr)
            }
        }
        
        return gaps
    }
    
}
