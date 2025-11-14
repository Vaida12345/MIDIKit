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
    public func downbeats() -> [Double] {
        guard !sustains.isEmpty else { return [] }
        var downbeats: [Double] = [0]
        var onset: Double = 0
        
        var durations = self.sustainDurations()
        let regions = self.regions()
        
        let baseline = self.baselineBarLength()
        let chords = self.chords()
        
        var durationIndex = 0
        while durationIndex < durations.count {
            let duration = durations[durationIndex]
            guard let region = regions.first(after: onset) else { break }
            
            func append(about beats: Double) {
                guard let nextChordIndex = chords.firstIndex(after: beats) else {
                    // maybe crossed the end?
                    downbeats.append(beats)
                    return
                }
                
                guard nextChordIndex > 0 else {
                    downbeats.append(chords[nextChordIndex].leadingOnset)
                    return
                }
                
                let next = chords[nextChordIndex]
                let prev = chords[nextChordIndex - 1]
                
                let nextDistance = abs(next.leadingOnset - beats)
                let prevDistance = abs(prev.leadingOnset - beats)
                
                // snap to nearest chord
                downbeats.append(nextDistance < prevDistance ? next.leadingOnset : prev.leadingOnset)
            }
            
            
            if duration > baseline * 1.5 {
                // duration significantly higher than baseline
                let baselineLoss = duration.remainder(dividingBy: baseline)
                let newFit = IndexedContainer.baselineBarLength(samples: region.notes.map({ ($0.duration, 1) }) + [(duration, 1)])
                let newLoss = duration.remainder(dividingBy: newFit)
                
                let base = abs(newLoss) < abs(baselineLoss) ? newFit : baseline
                let measuresInDuration = (duration / base).rounded()
                
                let divisor = duration / measuresInDuration
                // naive split for now
                for i in 1...Int(measuresInDuration) {
                    let start = onset + divisor * Double(i)
                    append(about: start)
                }
                
                onset += duration
            } else if duration < baseline / 2 {
                // too short, must be error, merge with next
                if durationIndex < durations.count - 1 {
                    durations[durationIndex + 1] += durations[durationIndex]
                }
            } else {
                onset += duration
                append(about: onset)
            }
            
            durationIndex &+= 1
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
