//
//  SingleNotes.swift
//  PianoVisualizer
//
//  Created by Vaida on 11/25/24.
//

import AudioToolbox


public struct SingleNotes: ArrayRepresentable {
    
    public var contents: [ReferenceNote]
    
    @inlinable
    public init(_ contents: [ReferenceNote]) {
        self.contents = contents
    }
    
    /// Returns the first note whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
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
    @inlinable
    public func first(after timeStamp: MusicTimeStamp) -> Element? {
        self.firstIndex(after: timeStamp).map { self.contents[$0] }
    }
    
    /// Returns the last note whose offset is less than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
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
    
    @inlinable
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
    
    @inlinable
    public func nearestIndex(to timeStamp: MusicTimeStamp) -> Index? {
        guard !self.isEmpty else { return nil }
        
        var left = 0
        var right = self.count - 1
        
        // Binary search for the nearest interval
        while left <= right {
            let mid = (left + right) / 2
            let current = self[mid]
            
            if timeStamp >= current.onset && timeStamp <= current.offset {
                return mid
            } else if timeStamp < current.onset {
                right = mid - 1
            } else {
                left = mid + 1
            }
        }
        
        // Compare the closest intervals on either side of the timestamp
        let closestLeft = right >= 0 ? self[right] : nil
        let closestRight = left < self.count ? self[left] : nil
        
        if let leftInterval = closestLeft, let rightInterval = closestRight {
            return abs(leftInterval.offset - timeStamp) <= abs(rightInterval.onset - timeStamp) ? right : left
        } else if closestLeft != nil {
            return right
        } else {
            return left
        }
    }
    
    @inlinable
    public func nearest(to timeStamp: Double) -> Element? {
        self.nearestIndex(to: timeStamp).map { self[$0] }
    }
    
    func nearest(
        to timestamp: Double,
        isValid: (Element) -> Bool
    ) -> Element? {
        guard !self.isEmpty else { return nil }
        
        var left = 0
        var right = self.count - 1
        
        // Binary search for the nearest valid interval
        while left <= right {
            let mid = (left + right) / 2
            let current = self[mid]
            
            if isValid(current), timestamp >= current.onset && timestamp <= current.offset {
                return current
            } else if timestamp < current.onset {
                right = mid - 1
            } else {
                left = mid + 1
            }
        }
        
        // Compare the closest valid intervals on either side of the timestamp
        var closestLeft: Element?
        var closestRight: Element?
        
        if right >= 0, isValid(self[right]) {
            closestLeft = self[right]
        }
        if left < self.count, isValid(self[left]) {
            closestRight = self[left]
        }
        
        if let leftInterval = closestLeft, let rightInterval = closestRight {
            return abs(leftInterval.onset - timestamp) <= abs(rightInterval.onset - timestamp) ? leftInterval : rightInterval
        } else if let leftInterval = closestLeft {
            return leftInterval
        } else {
            return closestRight
        }
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
