//
//  DisjointIntervals.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

/// Sorted, non-overlapping intervals: both onsets and offsets are increasing.
///
/// This protocol has no protocol requirement, other than the fact that it's contents should be increasing.
public protocol DisjointIntervals: RandomAccessCollection where Element: Interval {

}


extension DisjointIntervals where Index == Int {

    /// Returns the first index whose element does not satisfy `isBefore`.
    ///
    /// - Precondition: `isBefore` is true for a prefix of the collection and false for the rest.
    ///
    /// - Complexity: O(log *n*), branchless binary search.
    @inlinable
    func partitionPoint(_ isBefore: (Element) -> Bool) -> Int {
        self.partitionPoint(in: self.startIndex..<self.endIndex, isBefore)
    }

    /// Returns the first index in `range` whose element does not satisfy `isBefore`, or `range.upperBound` if every element does.
    ///
    /// - Precondition: `range` lies within `startIndex..<endIndex`. `isBefore` is true for a prefix of `range` and false for the rest.
    ///
    /// - Complexity: O(log *m*), branchless binary search, where *m* is the length of `range`.
    @inlinable
    func partitionPoint(in range: Range<Int>, _ isBefore: (Element) -> Bool) -> Int {
        var base = range.lowerBound
        var length = range.upperBound &- range.lowerBound
        guard length > 0 else { return base }
        while length > 1 { // almost always true, so predictable.
            let half = length &>> 1
            base = isBefore(self[base &+ half]) ? base &+ half : base
            length &-= half
        }
        return base &+ (isBefore(self[base]) ? 1 : 0)
    }

    /// Returns the first index whose element does not satisfy `isBefore`, starting the search at `cursor`.
    ///
    /// The cursor is only a hint: the result is the same as ``partitionPoint(_:)`` for any `cursor`. When the result is at or after `cursor`, it is found with a galloping search; otherwise, with a binary search of the elements before `cursor`.
    ///
    /// - Precondition: `cursor` is in `startIndex...endIndex`. `isBefore` is true for a prefix of the collection and false for the rest.
    ///
    /// - Complexity: O(log *d*), where *d* is the distance from `cursor` to the result, when the result is at or after `cursor`. O(log *n*) otherwise.
    @inlinable
    func partitionPoint(from cursor: Int, _ isBefore: (Element) -> Bool) -> Int {
        precondition(cursor >= self.startIndex && cursor <= self.endIndex, "cursor \(cursor) is out of \(self.startIndex)...\(self.endIndex)")

        // The query moved backward: the result is before `cursor`.
        if cursor > self.startIndex && !isBefore(self[cursor &- 1]) {
            return self.partitionPoint(in: self.startIndex..<cursor, isBefore)
        }

        // Galloping search. Every element before `low` satisfies `isBefore`; probe `low + step - 1`, doubling `step` until an element does not.
        var low = cursor
        var step = 1
        while true {
            let high = low &+ step
            guard high <= self.endIndex else {
                return self.partitionPoint(in: low..<self.endIndex, isBefore)
            }
            if !isBefore(self[high &- 1]) {
                return self.partitionPoint(in: low..<(high &- 1), isBefore)
            }
            low = high
            step &<<= 1
        }
    }

    /// Returns the index of the interval containing `timeStamp`, or else of the neighbor closest to `timeStamp` within `tolerance`.
    ///
    /// - Parameters:
    ///   - partitionPoint: The index of the first interval whose offset is not less than `timeStamp`.
    ///   - timeStamp: The time stamp to look up.
    ///   - tolerance: The largest distance from `timeStamp` to an interval that does not contain it.
    @inlinable
    func index(around partitionPoint: Int, at timeStamp: Double, tolerance: Double) -> Int? {
        // `self[partitionPoint]` is the first interval not ending before `timeStamp`; it contains `timeStamp` unless it starts after it. Intervals are disjoint, so no other interval can contain it.
        if partitionPoint < self.endIndex && self[partitionPoint].onset <= timeStamp {
            return partitionPoint
        }

        // Otherwise, only the neighbors on either side can be the closest.
        let left = partitionPoint &- 1
        let leftDistance = left >= self.startIndex ? timeStamp - self[left].offset : .infinity
        let rightDistance = partitionPoint < self.endIndex ? self[partitionPoint].onset - timeStamp : .infinity

        let isLeft = leftDistance <= rightDistance // the earlier on a tie
        let distance = isLeft ? leftDistance : rightDistance
        let index = isLeft ? left : partitionPoint
        return distance <= tolerance && distance < .infinity ? index : nil
    }

}


extension DisjointIntervals where Index == Int {

    /// Returns the index of the first interval that lies entirely after the given time stamp.
    ///
    /// An interval lies entirely after `timeStamp` when its onset is greater than `timeStamp`. An interval that starts exactly at `timeStamp` is not after it.
    ///
    /// - Complexity: O(log *n*), branchless binary search.
    ///
    /// - SeeAlso: ``firstIndex(after:from:)``
    @inlinable
    public func firstIndex(after timeStamp: Double) -> Int? {
        let index = self.partitionPoint { $0.onset <= timeStamp }
        return index == self.endIndex ? nil : index
    }

    /// Returns the index of the first interval that lies entirely after the given time stamp, starting the search at `cursor`.
    ///
    /// Use this method when queries move forward in time: pass the previous result as `cursor`.
    ///
    /// ```swift
    /// var cursor = intervals.startIndex
    /// for timeStamp in timeStamps { // in increasing order
    ///     cursor = intervals.firstIndex(after: timeStamp, from: cursor)
    ///     guard cursor != intervals.endIndex else { break }
    ///     // use intervals[cursor]
    /// }
    /// ```
    ///
    /// A query that moves backward in time is still answered correctly, with a search of the intervals before `cursor`.
    ///
    /// - Parameters:
    ///   - timeStamp: The time stamp to search after.
    ///   - cursor: Where to start the search, in `startIndex...endIndex`. Typically the result of the previous query.
    ///
    /// - Returns: The index of the first interval whose onset is greater than `timeStamp`, or `endIndex` if there is no such interval. Unlike ``firstIndex(after:)``, the result is never `nil`, so it can be passed back as the next `cursor`.
    ///
    /// - Complexity: O(log *d*), where *d* is the distance from `cursor` to the result.
    @inlinable
    public func firstIndex(after timeStamp: Double, from cursor: Int) -> Int {
        self.partitionPoint(from: cursor) { $0.onset <= timeStamp }
    }

    /// Returns the first interval that lies entirely after the given time stamp.
    ///
    /// An interval lies entirely after `timeStamp` when its onset is greater than `timeStamp`. An interval that starts exactly at `timeStamp` is not after it.
    ///
    /// - Complexity: O(log *n*), branchless binary search.
    @inlinable
    public func first(after timeStamp: Double) -> Element? {
        self.firstIndex(after: timeStamp).map { self[$0] }
    }

    /// Returns the index of the last interval that lies entirely before the given time stamp.
    ///
    /// An interval lies entirely before `timeStamp` when its offset is less than `timeStamp`. An interval that ends exactly at `timeStamp` is not before it.
    ///
    /// - Complexity: O(log *n*), branchless binary search.
    ///
    /// - SeeAlso: ``lastIndex(before:from:)``
    @inlinable
    public func lastIndex(before timeStamp: Double) -> Int? {
        let index = self.partitionPoint { $0.offset < timeStamp } &- 1
        return index < self.startIndex ? nil : index
    }

    /// Returns the index of the last interval that lies entirely before the given time stamp, starting the search at `cursor`.
    ///
    /// Use this method when queries move forward in time: pass the previous result as `cursor`, or `startIndex` when there was none. The cursor is only a hint: any value in `startIndex...endIndex` gives the same result as ``lastIndex(before:)``, and the closer it is to the result, the faster the search.
    ///
    /// - Parameters:
    ///   - timeStamp: The time stamp to search before.
    ///   - cursor: Where to start the search, in `startIndex...endIndex`.
    ///
    /// - Returns: The index of the last interval whose offset is less than `timeStamp`, or `nil` if there is no such interval.
    ///
    /// - Complexity: O(log *d*), where *d* is the distance from `cursor` to the result, when the query moves forward in time. O(log *n*) otherwise.
    @inlinable
    public func lastIndex(before timeStamp: Double, from cursor: Int) -> Int? {
        let index = self.partitionPoint(from: cursor) { $0.offset < timeStamp } &- 1
        return index < self.startIndex ? nil : index
    }

    /// Returns the last interval that lies entirely before the given time stamp.
    ///
    /// An interval lies entirely before `timeStamp` when its offset is less than `timeStamp`. An interval that ends exactly at `timeStamp` is not before it.
    ///
    /// - Complexity: O(log *n*), branchless binary search.
    @inlinable
    public func last(before timeStamp: Double) -> Element? {
        self.lastIndex(before: timeStamp).map { self[$0] }
    }

    /// Returns the index of the interval at the given time stamp.
    ///
    /// The interval at `timeStamp` is the one that contains it, bounds inclusive. When no interval contains `timeStamp`, it is the interval closest to `timeStamp`, if that is within `tolerance`.
    ///
    /// When several intervals lie within `tolerance`, which happens when they are closer together than twice `tolerance`, the one closest to `timeStamp` is returned. On an exact tie, the earlier one is returned.
    ///
    /// - Parameters:
    ///   - timeStamp: The time stamp to look up.
    ///   - tolerance: The largest distance from `timeStamp` to an interval that does not contain it. It must not be negative.
    ///
    /// - Complexity: O(log *n*), branchless binary search.
    ///
    /// - SeeAlso: ``index(at:tolerance:from:)``
    @inlinable
    public func index(at timeStamp: Double, tolerance: Double = 0) -> Int? {
        let partitionPoint = self.partitionPoint { $0.offset < timeStamp }
        return self.index(around: partitionPoint, at: timeStamp, tolerance: tolerance)
    }

    /// Returns the index of the interval at the given time stamp, starting the search at `cursor`.
    ///
    /// The result is the same as ``index(at:tolerance:)``. Use this method when queries move forward in time: pass the previous result as `cursor`, or `startIndex` when there was none. The cursor is only a hint: any value in `startIndex...endIndex` gives the same result, and the closer it is to the result, the faster the search.
    ///
    /// - Parameters:
    ///   - timeStamp: The time stamp to look up.
    ///   - tolerance: The largest distance from `timeStamp` to an interval that does not contain it. It must not be negative.
    ///   - cursor: Where to start the search, in `startIndex...endIndex`.
    ///
    /// - Complexity: O(log *d*), where *d* is the distance from `cursor` to the result, when the query moves forward in time. O(log *n*) otherwise.
    @inlinable
    public func index(at timeStamp: Double, tolerance: Double = 0, from cursor: Int) -> Int? {
        let partitionPoint = self.partitionPoint(from: cursor) { $0.offset < timeStamp }
        return self.index(around: partitionPoint, at: timeStamp, tolerance: tolerance)
    }

    /// Returns the interval that contains the given time stamp, bounds inclusive.
    ///
    /// - Complexity: O(log *n*), branchless binary search.
    ///
    /// - SeeAlso: ``index(at:tolerance:)``
    @inlinable
    public subscript(at timeStamp: Double) -> Element? {
        self.index(at: timeStamp).map { self[$0] }
    }

    /// Returns the indices of the intervals that overlap the given range.
    ///
    /// An interval overlaps `range` when they share at least one time stamp, bounds inclusive: an interval that ends exactly at `range.lowerBound`, or starts exactly at `range.upperBound`, overlaps it. As the intervals are disjoint and sorted, the overlapping intervals are always consecutive.
    ///
    /// - Returns: The indices of the overlapping intervals, empty if there are none.
    ///
    /// - Complexity: O(log *n*), two branchless binary searches.
    @inlinable
    public func indices(overlapping range: ClosedRange<Double>) -> Range<Int> {
        let lowerBound = self.partitionPoint { $0.offset < range.lowerBound }
        let upperBound = self.partitionPoint(in: lowerBound..<self.endIndex) { $0.onset <= range.upperBound }
        return lowerBound..<upperBound
    }

    /// Returns whether any interval overlaps the given interval, bounds inclusive.
    ///
    /// - Precondition: The onset of `interval` is not greater than its offset.
    ///
    /// - Complexity: O(log *n*), two branchless binary searches.
    ///
    /// - SeeAlso: ``indices(overlapping:)``
    @inlinable
    public func overlaps(with interval: some Interval) -> Bool {
        !self.indices(overlapping: interval.onset...interval.offset).isEmpty
    }

    /// Returns whether the intervals meet the requirements of ``DisjointIntervals``.
    ///
    /// The requirements are met when no interval ends before it starts, and every interval ends before the next one starts. Two intervals that touch, one ending exactly where the next starts, do not meet them.
    ///
    /// Use this method in an `assert` when you create a type that conforms to ``DisjointIntervals``, as the protocol cannot enforce its requirements.
    ///
    /// - Complexity: O(*n*).
    @inlinable
    public func isValidDisjointIntervals() -> Bool {
        var index = self.startIndex
        while index < self.endIndex {
            let interval = self[index]
            guard interval.onset <= interval.offset else { return false }
            let next = index &+ 1
            if next < self.endIndex && !(interval.offset < self[next].onset) {
                return false
            }
            index = next
        }
        return true
    }

}
