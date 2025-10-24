//
//  Region.swift
//  MIDIKit
//
//  Created by Vaida on 2025-10-24.
//

import OSLog
import Essentials


extension IndexedContainer {
    
    public struct Region: Comparable {
        
        public let onset: Double
        
        public var duration: Double { self.offset - self.onset }
        
        public let offset: Double
        
        
        public let notes: [ReferenceNote]
        
        
        init(notes: [ReferenceNote]) {
            assert(!notes.isEmpty)
            
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
    public func regions() -> [Region] {
        var notes = (0..<self.contents.count).map({ ReferenceNote(self.contents.baseAddress! + $0) })
        notes.sort(by: { $0.offset > $1.offset })
        
        var sustainsIterator = self.sustains.reversed().makeIterator()
        var _sustain = sustainsIterator.next()
        
        var groups: [[ReferenceNote]] = []
        var currentGroup: [ReferenceNote] = []
        
        var i = notes.startIndex
        while i < notes.endIndex {
            guard let sustain = _sustain else {
                // push all remaining notes
                currentGroup.append(contentsOf: notes[i...])
                break
            }
            
            let value = notes[i]
            let shouldCreateNewGroup = value.offset < sustain.onset
            if shouldCreateNewGroup {
                groups.append(currentGroup)
                _sustain = sustainsIterator.next()
                currentGroup = []
            }
            currentGroup.append(value)
            
            i &+= 1
        }
        
        groups.append(currentGroup)
        
        assert(groups.map(\.count).sum == self.contents.count, "Validation failed, \(#function) is broken.")
        return groups.map(Region.init)
    }
    
}
