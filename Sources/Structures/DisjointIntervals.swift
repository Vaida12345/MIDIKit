//
//  DisjointIntervals.swift
//  MIDIKit
//
//  Created by Vaida on 1/3/25.
//

/// Intervals whose `onset` and `offset` cannot overlap.
public protocol DisjointIntervals: SortedIntervals {
    
}


extension DisjointIntervals {
    
    /// Returns the first interval whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public func firstIndex(after timeStamp: Double) -> Index? {
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
    
    /// Returns the first interval whose onset is greater than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public func first(after timeStamp: Double) -> Element? {
        self.firstIndex(after: timeStamp).map { self.contents[$0] }
    }
    
    /// Returns the last interval whose offset is less than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public func lastIndex(before timeStamp: Double) -> Index? {
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
    
    /// Returns the last interval whose offset is less than `timeStamp`.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public func last(before timeStamp: Double) -> Element? {
        self.lastIndex(before: timeStamp).map { self.contents[$0] }
    }
    
    /// Returns the interval at the given time stamp, bounds inclusive.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public func index(at timeStamp: Double) -> Index? {
        var low = 0
        var high = self.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let interval = self[mid]
            
            if timeStamp >= interval.onset && timeStamp <= interval.offset {
                return mid
            } else if timeStamp < interval.onset {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        
        return nil
    }
    
    /// Returns the interval at the given time stamp, bounds inclusive.
    ///
    /// This structure assumes that there are no overlapping timestamps.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public subscript(at timeStamp: Double) -> Element? {
        self.index(at: timeStamp).map { self.contents[$0] }
    }
    
    /// Returns the nearest interval to  the given time stamp.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public func nearestIndex(to timeStamp: Double) -> Index? {
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
    
    /// Returns the nearest interval to  the given time stamp.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public func nearest(to timeStamp: Double) -> Element? {
        self.nearestIndex(to: timeStamp).map { self[$0] }
    }
    
    /// Returns the nearest interval to  the given time stamp.
    ///
    /// - Complexity: O(log *n*), binary search.
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
    
    
}
