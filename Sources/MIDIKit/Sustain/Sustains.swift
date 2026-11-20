//
//  Sustains.swift
//  MIDIKit
//
//  Created by Vaida on 9/3/24.
//

import AudioToolbox
import DetailedDescription
import Intervals


/// Sustain events sorted by onset, each ending at least a minimum gap before the next one starts.
///
/// Every pedal change is kept: when the pedal is lifted and pressed again, the sustain before ends a small gap before the one after starts, rather than merging the two into one long pedal. A lifted pedal releases the notes it held, both in playback and in analyses such as normalizing note lengths, so the change matters even when it is instantaneous. The gap keeps the pedal up and the pedal down on different ticks when the sustains are written to a file.
///
/// The sustains are cleaned up on creation and on every insertion, so they always meet the requirements of ``Intervals/DisjointIntervals``. See ``init(_:minimumGap:)`` for the rules.
public struct MIDISustainEvents: Sendable, Equatable, DetailedStringConvertible {

    /// The sustains, sorted by onset, each ending at least the minimum gap before the next one starts.
    public private(set) var contents: [Element]


    /// Creates sustains from any sustains, cleaned up.
    ///
    /// - Sustains whose times are not finite, or that end before they start, are dropped. The rest are sorted by onset.
    /// - Two sustains whose onsets are closer than `minimumGap` are one pedal change, and are merged into one, with the earlier onset and the later offset.
    /// - Every sustain ends at least `minimumGap` before the next one starts: the earlier one is shortened, and the onset of the later one, the pedal change, stays. When the earlier one lasted longer, the later one is extended to its end, so the pedal stays down as long as before.
    /// - Unlike notes, a sustain left shorter than `minimumGap` is kept, as dropping it would leave notes unsustained.
    ///
    /// - Parameters:
    ///   - sustains: The source sustains, in any order.
    ///   - minimumGap: The minimum gap between consecutive sustains, in beats. It must be finite and greater than zero. The default value is `1/128`, the same as the minimum gap between consecutive notes of `IndexedTrack`, and a whole number of ticks of ``MIDIContainer/writeResolution``.
    ///
    /// - Complexity: O(*n* log *n*), where *n* is the number of sustains.
    public init(_ sustains: some Sequence<MIDISustainEvent> = [], minimumGap: Double = 1/128) {
        precondition(minimumGap.isFinite && minimumGap > 0, "minimumGap must be finite and greater than zero")
        var sorted = sustains.filter(Self.isValid)
        sorted.sort(by: Self.isOrdered)
        self.contents = Self.normalized(sorted, minimumGap: minimumGap)
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


    /// Inserts a sustain, cleaning up as ``init(_:minimumGap:)`` does.
    ///
    /// - Parameters:
    ///   - sustain: The sustain to insert. It is ignored if its times are not finite, or if it ends before it starts.
    ///   - minimumGap: The minimum gap between consecutive sustains, in beats. The default value is `1/128`.
    ///
    /// - Complexity: O(*n*), where *n* is the number of sustains.
    public mutating func insert(_ sustain: MIDISustainEvent, minimumGap: Double = 1/128) {
        precondition(minimumGap.isFinite && minimumGap > 0, "minimumGap must be finite and greater than zero")
        guard Self.isValid(sustain) else { return }

        // The first position whose sustain comes after `sustain`.
        var low = 0
        var high = self.contents.count
        while low < high {
            let middle = (low &+ high) / 2
            if Self.isOrdered(sustain, self.contents[middle]) { high = middle } else { low = middle &+ 1 }
        }

        var contents = self.contents
        contents.insert(sustain, at: low)
        self.contents = Self.normalized(contents, minimumGap: minimumGap)
    }

    /// Inserts sustains, cleaning up as ``init(_:minimumGap:)`` does.
    ///
    /// - Parameters:
    ///   - other: The sustains to insert.
    ///   - minimumGap: The minimum gap between consecutive sustains, in beats. The default value is `1/128`.
    ///
    /// - Complexity: O(*n* + *m*), where *n* and *m* are the numbers of sustains in `self` and `other`.
    public mutating func insert(contentsOf other: MIDISustainEvents, minimumGap: Double = 1/128) {
        precondition(minimumGap.isFinite && minimumGap > 0, "minimumGap must be finite and greater than zero")

        var merged: [MIDISustainEvent] = []
        merged.reserveCapacity(self.contents.count &+ other.contents.count)
        var lhs = 0
        var rhs = 0
        while lhs < self.contents.count || rhs < other.contents.count {
            if rhs == other.contents.count || (lhs < self.contents.count && !Self.isOrdered(other.contents[rhs], self.contents[lhs])) {
                merged.append(self.contents[lhs])
                lhs &+= 1
            } else {
                merged.append(other.contents[rhs])
                rhs &+= 1
            }
        }
        self.contents = Self.normalized(merged, minimumGap: minimumGap)
    }


    /// Returns the sustains, each transformed, keeping the spacing between them where it stays valid.
    ///
    /// Use this for transforms that move times without reordering them, such as a change of tempo or a shift. When the result is still sorted and disjoint it is kept as is, so the gaps the sustains were created with are not imposed again; otherwise it is cleaned up as ``init(_:minimumGap:)`` does, with the default gap.
    ///
    /// - Parameter transform: Returns the new sustain, or `nil` to remove it.
    ///
    /// - Complexity: O(*n*), or O(*n* log *n*) when the result needs cleaning up.
    package func transformed(_ transform: (MIDISustainEvent) -> MIDISustainEvent?) -> MIDISustainEvents {
        let sustains = self.contents.compactMap(transform)
        var result = self
        result.contents = sustains
        return sustains.allSatisfy(Self.isValid) && result.isValidDisjointIntervals() ? result : MIDISustainEvents(sustains)
    }

    /// Whether a sustain has finite times and does not end before it starts.
    private static func isValid(_ sustain: MIDISustainEvent) -> Bool {
        sustain.onset.isFinite && sustain.offset.isFinite && sustain.onset <= sustain.offset
    }

    /// The order of sustains: by onset, then by offset.
    private static func isOrdered(_ lhs: MIDISustainEvent, _ rhs: MIDISustainEvent) -> Bool {
        lhs.onset < rhs.onset || (lhs.onset == rhs.onset && lhs.offset < rhs.offset)
    }

    /// Merges the sustains of one pedal change, and makes every sustain end at least `minimumGap` before the next one starts.
    ///
    /// - Precondition: `sorted` holds valid sustains, ordered by ``isOrdered(_:_:)``.
    ///
    /// - Complexity: O(*n*), where *n* is the number of sustains.
    private static func normalized(_ sorted: [MIDISustainEvent], minimumGap: Double) -> [MIDISustainEvent] {
        var result: [MIDISustainEvent] = []
        result.reserveCapacity(sorted.count)

        for var sustain in sorted {
            if let last = result.last {
                if sustain.onset - last.onset < minimumGap {
                    // The same pedal change.
                    result[result.count &- 1].offset = Swift.max(last.offset, sustain.offset)
                    continue
                }
                if sustain.onset - last.offset < minimumGap {
                    // A pedal change: the pedal is up for `minimumGap` before it, and stays down as long as before.
                    sustain.offset = Swift.max(last.offset, sustain.offset)
                    result[result.count &- 1].offset = Swift.max(sustain.onset - minimumGap, last.onset)
                }
            }
            result.append(sustain)
        }

        return result
    }


    public typealias Element = MIDISustainEvent

    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDISustainEvents>) -> any DescriptionBlockProtocol {
        descriptor.sequence("", of: self)
    }

}


extension MIDISustainEvents: ExpressibleByArrayLiteral, RandomAccessCollection, BidirectionalCollection, DisjointIntervals {

    @inlinable public var startIndex: Int { 0 }
    @inlinable public var endIndex: Int { self.contents.count }
    @inlinable public var count: Int { self.contents.count }

    @inlinable
    public subscript(position: Index) -> Element {
        self.contents[position]
    }

    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }

}
