//
//  Track + Transform.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import AudioToolbox


extension MIDITrack {
    
    /// Quantize the track.
    ///
    /// In a time signature of 4/4, A `beats` of 1 indicates a quarter note (one beat), regardless of time signature.
    ///
    /// - SeeAlso: ``MIDITrack``
    public mutating func quantize(by beats: MusicTimeStamp) {
        func _quantize(value: inout MusicTimeStamp) {
            value = (value / beats).rounded(.toNearestOrAwayFromZero) * beats
        }
        
        for i in 0..<self.notes.count {
            var duration = self.notes[i].duration
            _quantize(value: &duration) // duration then onset, as onset would change the duration.
            _quantize(value: &self.notes[i].onset)
            self.notes[i].duration = Swift.max(duration, 1/4)
        }
        
        for i in 0..<self.sustains.count {
            _quantize(value: &self.sustains[i].onset)
            _quantize(value: &self.sustains[i].offset)
        }
    }
    
    /// Returns the measures of the track.
    ///
    /// The measures are well-defined in MIDI. In a time signature of `n/m`, `n` `m`th notes go in one measure.
    ///
    /// The notes cannot be split in half. The measures record only the `onset`, ignoring the `offset`
    ///
    /// - Returns: The raw measures.
    public func measures(timeSignature: (Int, Int)) -> [MIDIMeasure] {
        let length = Double(timeSignature.0)
        
        func groupings<T>(_ elements: [T], upperBound: Double, feature: (T) -> MusicTimeStamp) -> [[T]] {
            
            var groups: [[T]] = []
            var current: [T] = []
            
            var lowerBound: Double = 0
            let elements = elements.sorted(by: { feature($0) < feature($1) })
            
            var index = 0
            while lowerBound < upperBound {
                var next: T? {
                    guard index < elements.count else { return nil }
                    return elements[index]
                }
                
                while let next,
                      feature(next) < lowerBound + length {
                    current.append(next)
                    index += 1
                }
                
                groups.append(current)
                current = []
                lowerBound += length
            }
            
            groups.append(current)
            
            assert(groups.count == Int(upperBound / length) + 2)
            
            return groups
        }
        
        guard !self.notes.isEmpty else { return [] }
        
        let upperBound = self.notes.map(\.offset).max()!
        let sustains = groupings(self.sustains.contents, upperBound: upperBound, feature: \.onset)
        let notes = groupings(self.notes.contents, upperBound: upperBound, feature: \.onset)
        
        assert(notes.count == sustains.count)
        
        return zip(notes, sustains).map({ MIDIMeasure(notes: MIDINotes($0.0), sustains: MIDISustainEvents($0.1)) })
    }
    
}
