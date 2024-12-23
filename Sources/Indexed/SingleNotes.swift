//
//  SingleNotes.swift
//  PianoVisualizer
//
//  Created by Vaida on 11/25/24.
//

import AudioToolbox


public struct SingleNotes: RandomAccessCollection {
    
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
    
    /// Returns the first note whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func firstIndex(after timeStamp: MusicTimeStamp) -> Index? {
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
            return left
        } else {
            return nil
        }
    }
    
    /// Returns the first note whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func first(after timeStamp: MusicTimeStamp) -> Element? {
        self.firstIndex(after: timeStamp).map { self.contents[$0] }
    }
    
    /// Returns the last note whose offset is less than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func lastIndex(before timeStamp: MusicTimeStamp) -> Index? {
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
            return left - 1
        } else {
            return nil
        }
    }
    
    /// Returns the last note whose offset is less than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public func last(before timeStamp: MusicTimeStamp) -> Element? {
        self.lastIndex(before: timeStamp).map { self.contents[$0] }
    }
    
    public func index(at timeStamp: Double) -> Index? {
        var low = 0
        var high = self.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let interval = self[mid]
            
            if timeStamp >= interval.onset && timeStamp < interval.offset {
                return mid
            } else if timeStamp < interval.onset {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        
        return nil
    }

    
    /// Returns the sustain at the given time stamp.
    ///
    /// This structure assumes that there are no overlapping timestamps.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public subscript(at timeStamp: MusicTimeStamp) -> Element? {
        self.index(at: timeStamp).map { self.contents[$0] }
    }
    
    public typealias Element = ReferenceNote
    
}
