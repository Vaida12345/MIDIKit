//
//  RunningAverage.swift
//  MIDIKit
//
//  Created by Vaida on 12/21/24.
//

import Essentials


/// The running average of notes, can be used to separate hands.
public struct RunningAverage {
    
    public var contents: [Element]
    
    
    /// Calculate the running average.
    ///
    /// Only the onset is considered.
    ///
    /// - Parameter runningLength: The default value is `4` beats, that is one measure in a 4/4 sheet.
    init(
        combinedNotes: IndexedNotes,
        runningLength: Double = 4
    ) async {
        var contents: [Element] = []
        combinedNotes.forEach { index, note in
            var notesMin = note.note
            var notesMax = note.note
            var j = combinedNotes.lastIndex(before: note.onset - runningLength * 2) ?? 0
            while j < combinedNotes.endIndex, combinedNotes[j].onset < note.onset + runningLength / 2 {
                if combinedNotes[j].offset > note.onset - runningLength / 2 {
                    let new = combinedNotes[j].note
                    if notesMin > new {
                        notesMin = new
                    } else if notesMax < new {
                        notesMax = new
                    }
                }
                
                j &+= 1
            }
            
            contents.append(Element(onset: note.onset, note: (notesMin + notesMax) / 2))
        }
        
        self.contents = contents
    }
    
    /// Returns the nearest element
    ///
    /// - Complexity: O(log *n*), binary search.
    public subscript(at target: Double) -> Element? {
        guard !self.contents.isEmpty else { return nil }
        
        var low = 0
        var high = self.contents.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            if self.contents[mid].onset == target {
                return self.contents[mid]
            } else if self.contents[mid].onset < target {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        
        let left = high >= 0 ? self.contents[high].onset : Double.greatestFiniteMagnitude
        let right = low < self.contents.count ? self.contents[low].onset : Double.greatestFiniteMagnitude
        
        return abs(left - target) <= abs(right - target) ? self.contents[high] : self.contents[low]
    }
    
    
    public struct Element {
        
        public let onset: Double
        
        public let note: UInt8
        
    }
    
}
