//
//  OverlappingIntervals.swift
//  MIDIKit
//
//  Created by Vaida on 1/3/25.
//

/// Intervals whose `onset` and `offset` can overlap.
public protocol OverlappingIntervals: SortedIntervals {
    
}


extension OverlappingIntervals {
    
    /// Returns the first interval whose onset is greater than `timeStamp`.
    ///
    /// When the onsets are overlapping, the one chosen is indeterministic.
    ///
    /// - Complexity: O(log *n*), binary search.
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
    /// When the onsets are overlapping, the one chosen is indeterministic.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func first(after timeStamp: Double) -> Element? {
        self.firstIndex(after: timeStamp).map({ self[$0] })
    }
    
    /// Returns the last interval whose offset is less than `timeStamp`.
    ///
    /// When the onsets are overlapping, the one chosen is indeterministic.
    ///
    /// - Complexity: O(log *n*), binary search.
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
    
    /// Returns the last interval whose onset is less than `timeStamp`.
    ///
    /// When the onsets are overlapping, the one chosen is indeterministic.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func lastIndex(onsetBefore timeStamp: Double) -> Index? {
        var left = 0
        var right = self.count
        
        while left < right {
            let mid = (left + right) / 2
            if self[mid].onset < timeStamp {
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
    /// When the onsets are overlapping, the one chosen is indeterministic.
    ///
    /// - Complexity: O(log *n*), binary search.
    @inlinable
    public func last(before timeStamp: Double) -> Element? {
        self.lastIndex(before: timeStamp).map { self[$0] }
    }
    
    
    /// Returns the intervals at the given time stamp. The returned sequence is sorted, same as `self`, bounds included.
    ///
    /// - Complexity: O(*n*), binary search then linear.
    public subscript(at timeStamp: Double) -> [Element] {
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
        for i in low..<self.count {
            let interval = self[i]
            if interval.onset > timeStamp {
                break
            }
            if interval.offset >= timeStamp {
                result.append(interval)
            }
        }
        
        return result
    }
    
    /// Returns the intervals in the given range. The returned sequence is sorted, same as `self`, bounds included.
    ///
    /// - Complexity: O(log *n*), binary search.
    public func range(_ range: ClosedRange<Double>) -> [Element] {
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
        for i in low..<self.count {
            let interval = self[i]
            if interval.onset > range.upperBound {
                break
            }
            if interval.offset >= range.upperBound {
                result.append(interval)
            }
        }
        
        return result
    }
    
}
