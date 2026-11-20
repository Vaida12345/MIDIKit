//
//  Indexed+Sustains.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit
import Intervals


extension IndexedTrack {

    /// Sustains sorted by onset and disjoint: each sustain ends before the next one starts.
    ///
    /// A value never changes after it is created, so it always meets these invariants, and the queries of ``Intervals/DisjointIntervals`` work on it.
    public struct Sustains: RandomAccessCollection, Sendable, Equatable, Intervals::DisjointIntervals {

        /// The sustains, sorted and disjoint.
        public let contents: [MIDISustainEvent]

        /// Creates sustains from any sustains, cleaned up.
        ///
        /// Sustains whose times are not finite, or that end before they start, are dropped. The rest are sorted by onset, and those that overlap or touch are merged into one.
        ///
        /// - Parameter sustains: The source sustains, in any order.
        ///
        /// - Complexity: O(*n* log *n*), where *n* is the number of sustains.
        public init(_ sustains: some Sequence<MIDISustainEvent>) {
            var sorted = sustains.filter { sustain in
                sustain.onset.isFinite && sustain.offset.isFinite && sustain.onset <= sustain.offset
            }
            sorted.sort { $0.onset < $1.onset }

            var contents: [MIDISustainEvent] = []
            contents.reserveCapacity(sorted.count)
            for sustain in sorted {
                if let last = contents.last, sustain.onset <= last.offset {
                    contents[contents.count &- 1].offset = Swift.max(last.offset, sustain.offset)
                } else {
                    contents.append(sustain)
                }
            }
            self.contents = contents
        }

        /// Creates sustains from sustains that are already sorted and disjoint, without cleaning them up.
        ///
        /// - Precondition: `sustains` are sorted by onset, and each ends before the next one starts. Checked with an `assert`.
        ///
        /// - Parameter sustains: The sorted, disjoint sustains.
        package init(validated sustains: [MIDISustainEvent]) {
            self.contents = sustains
            assert(self.isValidDisjointIntervals(), "The sustains must be sorted and disjoint.")
        }

        @inlinable public var startIndex: Int { 0 }
        @inlinable public var endIndex: Int { self.contents.count }
        @inlinable public var count: Int { self.contents.count }
        @inlinable public var isEmpty: Bool { self.contents.isEmpty }

        /// Returns the sustain at the given position.
        ///
        /// - Parameter index: A position in `0..<count`.
        @inlinable public subscript(index: Int) -> MIDISustainEvent { self.contents[index] }

    }

}
