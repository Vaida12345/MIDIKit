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
    public func downbeats() async -> [Double] {
        guard !sustains.isEmpty else { return [] }
        var downbeats: [Double] = [0]
        var onset: Double = 0
        
        let durations = self.sustainDurations() + [self.sustains.last!.duration]
        let regions = self.regions()
        print(regions.count)
        assert(durations.count == regions.count)
        let contents = Array(zip(durations, regions))
        
        let baseline = self.baselineBarLength()
        
        var i = 0
        while i < contents.count {
            let (duration, region) = contents[i]
            if duration > baseline * 3, onset == 0 {
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
                    downbeats.append(start)
                }
                
                onset = duration
            }
            
            i &+= 1
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
