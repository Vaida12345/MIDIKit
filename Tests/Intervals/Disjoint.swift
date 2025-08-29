//
//  Disjoint.swift
//  MIDIKit
//
//  Created by Vaida on 2025-08-29.
//

import Testing
import MIDIKit


private struct DisjointInterval: ArrayRepresentable, DisjointIntervals {
    
    var contents: [MIDISustainEvent]
    
    init(_ contents: [MIDISustainEvent]) {
        self.contents = contents
    }
    
    public typealias Element = MIDISustainEvent
    
}


@Suite
struct DisjointIntervalsTests {
    
    private let intervals = DisjointInterval([
        MIDISustainEvent(onset: 0, offset: 1),
        MIDISustainEvent(onset: 2, offset: 3),
        MIDISustainEvent(onset: 4, offset: 5),
    ])
    
    @Test func firstIndexAfter() {
        #expect(intervals.first(after: 0) == intervals[1])
        #expect(intervals.first(after: -0.1) == intervals[0])
        #expect(intervals.first(after: 1) == intervals[1])
        #expect(intervals.first(after: 4) == nil)
    }
    
    @Test func lastIndexBefore() {
        #expect(intervals.last(before: 4) == intervals[1])
        #expect(intervals.last(before: 5.1) == intervals[2])
        #expect(intervals.last(before: 3) == intervals[0])
        #expect(intervals.last(before: 2) == intervals[0])
        #expect(intervals.last(before: 0) == nil)
    }
    
    @Test func elementAt() {
        #expect(intervals[at: 0] == intervals[0])
        #expect(intervals[at: 0.5] == intervals[0])
        #expect(intervals[at: 1] == intervals[0])
        #expect(intervals[at: 1.5] == nil)
    }
    
    @Test func overlapsWith() {
        #expect(intervals.overlaps(with: MIDISustainEvent(onset: 0.5, offset: 2.5)))
        #expect(intervals.overlaps(with: MIDISustainEvent(onset: 0.5, offset: 0.75)))
        #expect(!intervals.overlaps(with: MIDISustainEvent(onset: 1.5, offset: 1.75)))
    }
    
}
