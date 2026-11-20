//
//  IntervalTree.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


/// Intervals sorted by onset, which may overlap, indexed for overlap queries.
///
/// The tree is implicit: the intervals stay in `base`, in onset order, and the position of each interval defines its place in a binary tree, as in Heng Li's cgranges. The only extra storage is ``maxOffsets``, one `Double` per interval. Overlap queries take O(log *n* + *k*), where *k* is the number of results, regardless of how long the intervals are.
///
/// An interval tree is an index over `base`, not a collection: every query returns indices of `base`, so read the intervals with `tree.base[index]`.
public struct IntervalTree<Base: RandomAccessCollection> where Base.Element: Interval, Base.Index == Int {
    
    /// The intervals, sorted by onset.
    public let base: Base
    
    /// The largest offset in the subtree rooted at each position, where position `j` is `base[base.startIndex + j]`.
    @usableFromInline let maxOffsets: [Double]
    
    /// Creates a tree from intervals and their precomputed ``maxOffsets``.
    ///
    /// - Precondition: `maxOffsets` is the result of ``buildMaxOffsets(for:)`` for `base`.
    @inlinable
    package init(_ base: Base, maxOffsets: [Double]) {
        assert(maxOffsets.count == base.count, "maxOffsets has \(maxOffsets.count) elements, base has \(base.count)")
        self.base = base
        self.maxOffsets = maxOffsets
    }
    
    /// Returns the indices of the intervals containing `timeStamp`, bounds inclusive, in increasing order.
    ///
    /// - Complexity: O(log *n* + *k*), where *k* is the number of results.
    @inlinable
    public func indices(containing timeStamp: Double) -> [Int] {
        self.indices(overlapping: timeStamp...timeStamp)
    }
    
    /// Returns the indices of the intervals overlapping `range`, bounds inclusive, in increasing order.
    ///
    /// An interval overlaps `range` when they share at least one time stamp: its onset is not after `range.upperBound`, and its offset is not before `range.lowerBound`.
    ///
    /// - Complexity: O(log *n* + *k*), where *k* is the number of results.
    @inlinable
    public func indices(overlapping range: ClosedRange<Double>) -> [Int] {
        var result: [Int] = []
        self._forEachIndex(overlapping: range) { index in
            result.append(index)
            return true
        }
        return result
    }
    
    /// Calls `body` with the index of each interval overlapping `range`, bounds inclusive, in increasing order, without allocating.
    ///
    /// - Complexity: O(log *n* + *k*), where *k* is the number of results.
    @inlinable
    public func forEachIndex<E: Error>(overlapping range: ClosedRange<Double>, _ body: (Int) throws(E) -> Void) throws(E) {
        try self._forEachIndex(overlapping: range) { (index) throws(E) -> Bool in
            try body(index)
            return true
        }
    }
    
    /// Returns whether any interval overlaps `range`, bounds inclusive. The search stops at the first one found.
    ///
    /// - Complexity: O(log *n*).
    @inlinable
    public func overlaps(_ range: ClosedRange<Double>) -> Bool {
        var found = false
        self._forEachIndex(overlapping: range) { _ in
            found = true
            return false
        }
        return found
    }

    /// Returns the intervals containing `timeStamp`, bounds inclusive, in onset order.
    ///
    /// - Complexity: O(log *n* + *k*), where *k* is the number of results.
    ///
    /// - SeeAlso: ``indices(containing:)``
    @inlinable
    public func intervals(containing timeStamp: Double) -> [Base.Element] {
        self.intervals(overlapping: timeStamp...timeStamp)
    }

    /// Returns the intervals overlapping `range`, bounds inclusive, in onset order.
    ///
    /// An interval overlaps `range` when they share at least one time stamp: its onset is not after `range.upperBound`, and its offset is not before `range.lowerBound`.
    ///
    /// - Complexity: O(log *n* + *k*), where *k* is the number of results.
    ///
    /// - SeeAlso: ``indices(overlapping:)``
    @inlinable
    public func intervals(overlapping range: ClosedRange<Double>) -> [Base.Element] {
        var result: [Base.Element] = []
        self._forEachIndex(overlapping: range) { index in
            result.append(self.base[index])
            return true
        }
        return result
    }

    /// Calls `body` with each interval overlapping `range`, bounds inclusive, in onset order, without allocating.
    ///
    /// - Complexity: O(log *n* + *k*), where *k* is the number of results.
    ///
    /// - SeeAlso: ``forEachIndex(overlapping:_:)``
    @inlinable
    public func forEach<E: Error>(overlapping range: ClosedRange<Double>, _ body: (Base.Element) throws(E) -> Void) throws(E) {
        try self._forEachIndex(overlapping: range) { (index) throws(E) -> Bool in
            try body(self.base[index])
            return true
        }
    }

}


extension IntervalTree: Sendable where Base: Sendable {
    
}


extension IntervalTree {
    
    /// Returns the largest offset in the subtree rooted at each position of `base`.
    ///
    /// Position `j` is at level `k`, the number of trailing one bits of `j`; its subtree spans positions `j - 2^k + 1 ... j + 2^k - 1`, clipped to `base`.
    ///
    /// - Precondition: `base` is sorted by onset.
    ///
    /// - Complexity: O(*n*).
    @inlinable
    public static func buildMaxOffsets(for base: Base) -> [Double] {
        let count = base.count
        guard count > 0 else { return [] }
        let start = base.startIndex
        
        // Every position starts at its own offset; leaves are then final.
        var maxOffsets = [Double](unsafeUninitializedCapacity: count) { buffer, initializedCount in
            var position = 0
            while position < count {
                buffer[position] = base[start &+ position].offset
                position &+= 1
            }
            initializedCount = count
        }
        
        maxOffsets.withUnsafeMutableBufferPointer { maxOffsets in
            // `lastPosition` is the rightmost real node at the current level, and `last` the largest offset in its subtree. It stands in for right children past the end.
            var lastPosition = (count &- 1) & ~1
            var last = maxOffsets[lastPosition]
            
            var level = 1
            while 1 &<< level <= count {
                let half = 1 &<< (level &- 1) // the distance from a node to its children
                var position = (half &<< 1) &- 1
                while position < count {
                    let left = maxOffsets[position &- half]
                    let right = position &+ half < count ? maxOffsets[position &+ half] : last
                    maxOffsets[position] = Swift.max(maxOffsets[position], Swift.max(left, right))
                    position &+= half &<< 2
                }
                
                // Move to the parent of `lastPosition`: a right child when bit `level` is set.
                lastPosition = (lastPosition &>> level) & 1 != 0 ? lastPosition &- half : lastPosition &+ half
                if lastPosition < count {
                    last = Swift.max(last, maxOffsets[lastPosition])
                }
                level &+= 1
            }
        }
        
        return maxOffsets
    }
    
    /// Creates a tree indexing the given intervals.
    ///
    /// - Precondition: `base` is sorted by onset, and no interval ends before it starts (checked with an `assert`).
    ///
    /// - Complexity: O(*n*).
    @inlinable
    public init(_ base: Base) {
        assert(Self.isSortedByOnset(base), "The intervals must be sorted by onset, and no interval may end before it starts.")
        self.init(base, maxOffsets: Self.buildMaxOffsets(for: base))
    }
    
    /// Returns whether `base` is sorted by onset, with no interval ending before it starts.
    @inlinable
    static func isSortedByOnset(_ base: Base) -> Bool {
        var index = base.startIndex
        while index < base.endIndex {
            let interval = base[index]
            guard interval.onset <= interval.offset else { return false }
            let next = index &+ 1
            if next < base.endIndex && base[next].onset < interval.onset {
                return false
            }
            index = next
        }
        return true
    }
    
}


extension IntervalTree {
    
    /// The level at or below which a subtree, at most 15 positions, is scanned linearly instead of walked.
    @inlinable
    static var linearScanLevel: Int { 3 }
    
    /// Calls `body` with the index of each interval overlapping `range`, bounds inclusive, in increasing order, until `body` returns `false`.
    ///
    /// This is an in-order walk of the implicit tree that needs no stack. In-order positions are increasing positions, so the node after a finished subtree is simply the position after its last one; the walk climbs back up with arithmetic alone. A subtree whose largest offset is before `range.lowerBound` is skipped, and as onsets only increase in order, the walk ends at the first onset after `range.upperBound`, or at the first position past the end.
    ///
    /// Always inlined, with no closure-taking calls inside, so that `body` is inlined at each call site instead of being called indirectly for every result.
    ///
    /// - Complexity: O(log *n* + *k*), where *k* is the number of results.
    @inlinable
    @inline(__always)
    func _forEachIndex<E: Error>(overlapping range: ClosedRange<Double>, _ body: (Int) throws(E) -> Bool) throws(E) {
        let count = self.base.count
        guard count > 0 else { return }
        let start = self.base.startIndex
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        
        // The subtree rooted at `position`, at `level`, comes next in order. When `isLeftDone`, its left subtree is already visited or skipped, and the node itself is next.
        let rootLevel = Int.bitWidth &- 1 &- count.leadingZeroBitCount
        var position = (1 &<< rootLevel) &- 1
        var level = rootLevel
        var isLeftDone = false
        
        while true {
            if !isLeftDone {
                if level <= Self.linearScanLevel {
                    // A small subtree, positions `position - 2^level + 1 ... position + 2^level - 1`: scan it in order.
                    let end = Swift.min(position &+ (1 &<< level), count)
                    var current = position &- (1 &<< level) &+ 1
                    while current < end {
                        let interval = self.base[start &+ current]
                        guard interval.onset <= upperBound else { return }
                        if interval.offset >= lowerBound {
                            guard try body(start &+ current) else { return }
                        }
                        current &+= 1
                    }
                    
                    // Climb: the next position is the ancestor whose left subtree just ended.
                    position &+= 1 &<< level
                    guard position < count else { return }
                    level = (~position).trailingZeroBitCount
                    isLeftDone = true
                    continue
                }
                
                // Descend left, unless the left subtree ends before the range. A left child past the end may still have real positions below it.
                let left = position &- (1 &<< (level &- 1))
                if left >= count || self.maxOffsets[left] >= lowerBound {
                    position = left
                    level &-= 1
                    continue
                }
            }
            
            // The node itself. Positions only increase from here, so one past the end, or an onset after the range, ends the walk.
            guard position < count else { return }
            let interval = self.base[start &+ position]
            guard interval.onset <= upperBound else { return }
            if interval.offset >= lowerBound {
                guard try body(start &+ position) else { return }
            }
            
            // Then the right subtree, unless it ends before the range: skip to the position after it, the next ancestor.
            level &-= 1
            let right = position &+ (1 &<< level)
            if right < count && self.maxOffsets[right] < lowerBound {
                position = right &+ (1 &<< level)
                guard position < count else { return }
                level = (~position).trailingZeroBitCount
                isLeftDone = true // also when this node was reached with its left subtree skipped
            } else {
                position = right
                isLeftDone = false
            }
        }
    }
    
}
