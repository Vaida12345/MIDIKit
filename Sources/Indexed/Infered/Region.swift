//
//  Region.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-24.
//

import OSLog
import Essentials


extension IndexedContainer {
    
    public struct Region: Interval, Comparable {
        
        public let id: UInt
        
        public let onset: Double
        
        public var duration: Double { self.offset - self.onset }
        
        public let offset: Double
        
        
        public let notes: [ReferenceNote]
        
        
        init(id: UInt, notes: [ReferenceNote]) {
            assert(!notes.isEmpty)
            
            self.id = id
            self.notes = notes
            self.onset = notes.min(of: \.onset)!
            self.offset = notes.max(of: \.offset)!
        }
        
        
        @inlinable
        public static func < (lhs: IndexedContainer.Region, rhs: IndexedContainer.Region) -> Bool {
            lhs.onset < rhs.onset
        }
        
    }
    
    
    /// Regions of the container, separated by pedals.
    ///
    /// This function uses `offset` and produce the regions reverse chronologically.
    ///
    /// ## Parameters
    /// - term self: Expected to be raw `self`, without preprocessing.
    ///
    /// - Returns: If `self` has no sustain, returns `self` as region.
    ///
    /// - Note: returned region count could be different to sustain count, as a region cannot be empty.
    public func regions() -> [Region] {
        guard !self.isEmpty else { return [] }
        var notes = (0..<self.contents.count).map({ ReferenceNote(self.contents.baseAddress! + $0) })
        if self.sustains.isEmpty {
            notes.sort(by: { $0.onset < $1.onset })
            return [Region(id: 0, notes: notes)]
        }
        notes.sort(by: { $0.offset > $1.offset })
        
        var sustainsIterator = self.sustains.reversed().makeIterator()
        var _sustain = sustainsIterator.next()
        
        var store: [ReferenceNote : UInt] = [:]
        store.reserveCapacity(notes.count)
        
        // first sweep
        var groupIndex: UInt = 0
        var i = notes.startIndex
        while i < notes.endIndex {
            guard let sustain = _sustain else {
                // push all remaining notes
                for i in notes[i...].indices {
                    store[notes[i]] = groupIndex
                }
                
                break
            }
            
            let shouldCreateNewGroup = notes[i].offset < sustain.onset
            if shouldCreateNewGroup {
                _sustain = sustainsIterator.next()
                groupIndex += 1
            }
            store[notes[i]] = groupIndex
            
            i &+= 1
        }
        
        var currRegion = store[notes.last!]! // the largest value
        // onset sweep
        notes.sort()
        
        i = notes.startIndex
        while i < notes.endIndex {
            if store[notes[i]]! < currRegion { // move on to next region
                currRegion = store[notes[i]]!
            } else if store[notes[i]]! > currRegion {
                // still in previous region? thats not right
                store[notes[i]] = currRegion
            }
            
            i &+= 1
        }
        
        return Dictionary(grouping: notes, by: { store[$0]! }).map({ Region(id: $0, notes: $1) }).sorted()
    }
    
}


extension Array<IndexedContainer.Region>: SortedIntervals {
    
}

extension Array<IndexedContainer.Region>: OverlappingIntervals {
    
}
