//
//  IndexedNotes.swift
//  PianoVisualizer
//
//  Created by Vaida on 11/25/24.
//

import AudioToolbox


public struct IndexedNotes: RandomAccessCollection {
    
    public var contents: [ReferenceNote]
    
    public var startIndex: Int {
        0
    }
    
    public var endIndex: Int {
        self.count
    }
    
    
    public var count: Int {
        self.contents.count
    }
    
    
    public subscript(position: Int) -> Element {
        self.contents[position]
    }
    
    
    /// Returns the first sustain whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func first(after timeStamp: MusicTimeStamp) -> Element? {
        var left = 0
        var right = self.count
        
        while left < right {
            let mid = (left + right) / 2
            if self[mid].onset > timeStamp {
                right = mid
            } else {
                left = mid + 1
            }
        }
        
        // After the loop, 'left' is the index of the first element greater than the value, if it exists.
        // Check if 'left' is within bounds and return the element if it exists.
        if left < self.count {
            return self[left]
        } else {
            return nil
        }
    }
    
    /// Returns the last sustain whose offset is less than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func last(before timeStamp: MusicTimeStamp) -> Element? {
        var left = 0
        var right = self.count
        
        while left < right {
            let mid = (left + right) / 2
            if self[mid].offset < timeStamp {
                left = mid + 1
            } else {
                right = mid
            }
        }
        
        if left > 0 {
            return self[left - 1]
        } else {
            return nil
        }
    }

    
    /// Returns the sustain at the given time stamp.
    ///
    /// This structure assumes that there are no overlapping timestamps.
    ///
    /// - Complexity: O(log *n*), binary search.
    public subscript(at timeStamp: MusicTimeStamp) -> Element? {
        var low = 0
        var high = self.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let interval = self[mid]
            
            if timeStamp >= interval.onset && timeStamp < interval.offset {
                return interval
            } else if timeStamp < interval.onset {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        
        return nil
    }
    
    public typealias Element = ReferenceNote
    
}
