//
//  OverlappingTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing


/// A concrete type implementing OverlappingIntervals for testing.
private struct Overlapping: ArrayRepresentable, OverlappingIntervals {

    var contents: [MIDISustainEvent]

    init(_ contents: [MIDISustainEvent]) {
        self.contents = contents
    }

    typealias Element = MIDISustainEvent

}


@Suite("OverlappingIntervals")
struct OverlappingIntervalsTests {

    private let intervals = Overlapping([
        MIDISustainEvent(onset: 0, offset: 2),
        MIDISustainEvent(onset: 1, offset: 3), // overlaps with [0]
        MIDISustainEvent(onset: 4, offset: 6),
        MIDISustainEvent(onset: 5, offset: 7), // overlaps with [2]
    ])

    @Test func firstIndexAfter() {
        #expect(intervals.firstIndex(after: -1) == 0)
        #expect(intervals.firstIndex(after: 0) == 1)
        #expect(intervals.firstIndex(after: 1) == 2)
        #expect(intervals.firstIndex(after: 6) == nil)
    }

    @Test func firstAfter() {
        #expect(intervals.first(after: 0) == intervals[1])
        #expect(intervals.first(after: 3) == intervals[2])
    }

    @Test func lastIndexBefore() {
        // lastIndex(before:) uses strict "<" on offset — offset must be strictly less
        #expect(intervals.lastIndex(before: 2.1) == 0)  // interval[0].offset(2) < 2.1
        #expect(intervals.lastIndex(before: 0) == nil)
        #expect(intervals.lastIndex(before: 8) == 3)
    }

    @Test func lastBefore() {
        #expect(intervals.last(before: 2.1) == intervals[0])
        #expect(intervals.last(before: 0) == nil)
    }

    @Test func lastIndexOnsetBefore() {
        #expect(intervals.lastIndex(onsetBefore: 3) == 1)
        #expect(intervals.lastIndex(onsetBefore: 1) == 0)
        #expect(intervals.lastIndex(onsetBefore: 0) == nil)
    }

    @Test func subscriptAtTimeStamp() {
        // 0-2, 1-3 overlap, so at time 1.5 both are active
        let at1_5 = intervals[at: 1.5]
        #expect(at1_5.count == 2)
        #expect(at1_5[0] == intervals[0])
        #expect(at1_5[1] == intervals[1])
    }

    @Test func subscriptAtTimeStampNoMatch() {
        #expect(intervals[at: -1].isEmpty)
        #expect(intervals[at: 8].isEmpty)
    }

    @Test func rangeQuery() {
        let inRange = intervals.range(1...5)
        // onset-based search: [0](0-2), [1](1-3), [2](4-6), [3](5-7) — all overlap
        #expect(inRange.count == 4)
    }

    @Test func rangeQueryNarrow() {
        let inRange = intervals.range(2.5...3.5)
        // Should only include [1] which spans 1-3
        #expect(inRange.count == 1)
        #expect(inRange[0] == intervals[1])
    }

    @Test func rangeQueryEmpty() {
        #expect(intervals.range(-5...(-1)).isEmpty)
    }

    @Test func emptyCollection() {
        let empty = Overlapping([])
        #expect(empty.first(after: 0) == nil)
        #expect(empty.last(before: 0) == nil)
        #expect(empty[at: 0].isEmpty)
        #expect(empty.range(0...1).isEmpty)
    }

    @Test func singleElement() {
        let single = Overlapping([MIDISustainEvent(onset: 1, offset: 3)])
        #expect(single.first(after: 0) == single[0])
        #expect(single.first(after: 2) == nil)
        #expect(single.last(before: 4) == single[0])
        #expect(single.last(before: 0) == nil)
        #expect(single[at: 2].count == 1)
        #expect(single[at: 0].isEmpty)
        #expect(single.range(2...4).count == 1)
    }

    @Test func boundaryInclusive() {
        let single = Overlapping([MIDISustainEvent(onset: 1, offset: 3)])
        // At exact onset, should match
        #expect(single[at: 1].count == 1)
        // At exact offset, should match
        #expect(single[at: 3].count == 1)
    }

}
