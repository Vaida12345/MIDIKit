//
//  CombinedNotes.swift
//  PianoVisualizer
//
//  Created by Vaida on 11/25/24.
//

import AudioToolbox


public struct CombinedNotes: RandomAccessCollection {
    
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

    
    /// Returns the sustain at the given time stamp. The returned sequence is sorted, same as `self`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public subscript(at timeStamp: MusicTimeStamp) -> [Element] {
        var low = 0
        var high = self.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let interval = self[mid]
            
            if interval.offset < timeStamp {
                low = mid + 1
            } else if interval.onset > timeStamp {
                high = mid - 1
            } else {
                // Point lies in this interval, move left to find the first occurrence
                high = mid - 1
            }
        }
        
        var result: [Element] = []
        // Check all intervals starting from the found position
        for i in low..<self.contents.count {
            let interval = self.contents[i]
            if interval.onset > timeStamp {
                break
            }
            if interval.offset >= timeStamp {
                result.append(interval)
            }
        }
        
        return result
    }
    
    /// Returns the sustain at the given time stamp. The returned sequence is sorted, same as `self`.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func range(_ range: ClosedRange<MusicTimeStamp>) -> [Element] {
        var low = 0
        var high = self.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let interval = self[mid]
            
            if interval.offset < range.lowerBound {
                low = mid + 1
            } else if interval.onset > range.upperBound {
                high = mid - 1
            } else {
                // Point lies in this interval, move left to find the first occurrence
                high = mid - 1
            }
        }
        
        var result: [Element] = []
        // Check all intervals starting from the found position
        for i in low..<self.contents.count {
            let interval = self.contents[i]
            if interval.onset > range.upperBound {
                break
            }
            if interval.offset >= range.upperBound {
                result.append(interval)
            }
        }
        
        return result
    }
    
    public typealias Element = ReferenceNote
    
}
