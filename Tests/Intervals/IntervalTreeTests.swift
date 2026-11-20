//
//  IntervalTreeTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
@testable
import Intervals


// MARK: - Support

private struct Span: Interval, Equatable {
    
    var onset: Double
    
    var offset: Double
    
    init(_ onset: Double, _ offset: Double) {
        self.onset = onset
        self.offset = offset
    }
    
}


/// A small deterministic generator, so the figures never change.
private struct TestRNG {
    
    var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed &* 0x9E3779B97F4A7C15 &+ 0x1234567
    }
    
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.count))
    }
    
}


/// Random overlapping intervals sorted by onset on a quarter-beat grid, so that query bounds often fall exactly on an onset or offset.
private struct Figure {
    
    /// The intervals, as a slice that may not start at `0`.
    let spans: ArraySlice<Span>
    
    let tree: IntervalTree<ArraySlice<Span>>
    
    /// Query time stamps covering the figure and a margin around it.
    let times: [Double]
    
    init(count: Int, rng: inout TestRNG) {
        var time = 0.0
        var spans: [Span] = []
        for _ in 0..<count {
            time += Double(rng.int(0...3)) * 0.25 // repeated onsets included
            let duration = rng.int(0...9) == 0 ? Double(rng.int(8...40)) * 0.25 : Double(rng.int(0...4)) * 0.25 // mostly short, sometimes held long; zero-length included
            spans.append(Span(time, time + duration))
        }
        let padding = rng.int(0...5)
        let full = Array(repeating: Span(-1, -1), count: padding) + spans
        self.spans = full[padding...]
        self.tree = IntervalTree(self.spans)
        
        let end = Int(((spans.map(\.offset).max() ?? 1) + 1) * 4)
        self.times = (-4...end).map { Double($0) / 4 }
    }
    
    /// The linear-scan answer every query is checked against.
    func expected(overlapping range: ClosedRange<Double>) -> [Int] {
        self.spans.indices.filter { self.spans[$0].onset <= range.upperBound && self.spans[$0].offset >= range.lowerBound }
    }
    
}


private struct StopError: Error {
    
}


// MARK: - Tests

/// The time limit fails a walk that never ends instead of hanging the test run.
@Suite(.timeLimit(.minutes(1)))
struct IntervalTreeTests {
    
    /// Sizes around every power of two exercise the positions past the end of the implicit tree.
    private static let sizes: [Int] = {
        var sizes = Set(0...20)
        for exponent in 2...8 {
            let power = 1 << exponent
            sizes.formUnion([power - 1, power, power + 1])
        }
        sizes.formUnion([100, 200, 300])
        return sizes.sorted()
    }()
    
    @Test(arguments: sizes)
    func maxOffsets(count: Int) {
        var rng = TestRNG(seed: UInt64(count) &+ 1)
        for _ in 0..<20 {
            let figure = Figure(count: count, rng: &rng)
            let maxOffsets = figure.tree.maxOffsets
            #expect(maxOffsets.count == count)
            
            let start = figure.spans.startIndex
            for position in 0..<count {
                let level = (~position).trailingZeroBitCount
                let lower = position - (1 << level) + 1
                let upper = Swift.min(position + (1 << level) - 1, count - 1)
                let expected = (lower...upper).map { figure.spans[start + $0].offset }.max()!
                #expect(maxOffsets[position] == expected, "count: \(count), position: \(position)")
            }
        }
    }
    
    @Test(arguments: sizes)
    func overlapping(count: Int) {
        var rng = TestRNG(seed: UInt64(count) &+ 1_000)
        for _ in 0..<10 {
            let figure = Figure(count: count, rng: &rng)
            for _ in 0..<60 {
                let lower = figure.times[rng.int(0...(figure.times.count - 1))]
                let upper = lower + Double(rng.int(0...16)) / 4
                let expected = figure.expected(overlapping: lower...upper)
                
                #expect(figure.tree.indices(overlapping: lower...upper) == expected, "count: \(count), range: \(lower)...\(upper)")
                #expect(figure.tree.overlaps(lower...upper) == !expected.isEmpty)
                
                var visited: [Int] = []
                figure.tree.forEachIndex(overlapping: lower...upper) { visited.append($0) }
                #expect(visited == expected)

                let expectedIntervals = expected.map { figure.spans[$0] }
                #expect(figure.tree.intervals(overlapping: lower...upper) == expectedIntervals)

                var visitedIntervals: [Span] = []
                figure.tree.forEach(overlapping: lower...upper) { visitedIntervals.append($0) }
                #expect(visitedIntervals == expectedIntervals)
            }
        }
    }
    
    @Test(arguments: sizes)
    func containing(count: Int) {
        var rng = TestRNG(seed: UInt64(count) &+ 2_000)
        for _ in 0..<10 {
            let figure = Figure(count: count, rng: &rng)
            for time in figure.times {
                let expected = figure.expected(overlapping: time...time)
                #expect(figure.tree.indices(containing: time) == expected, "count: \(count), time: \(time)")
                #expect(figure.tree.intervals(containing: time) == expected.map { figure.spans[$0] })
            }
        }
    }
    
    @Test
    func edgeCases() {
        let empty = IntervalTree([Span]())
        #expect(empty.indices(overlapping: 0...1).isEmpty)
        #expect(!empty.overlaps(0...1))
        
        let single = IntervalTree([Span(1, 2)])
        #expect(single.indices(containing: 1) == [0]) // bounds inclusive
        #expect(single.indices(containing: 2) == [0])
        #expect(single.indices(containing: 2.5).isEmpty)
        #expect(single.indices(overlapping: 2...3) == [0])
        #expect(single.indices(overlapping: 0...1) == [0])
        
        let point = IntervalTree([Span(0, 10), Span(1, 1), Span(1, 3), Span(5, 6)])
        #expect(point.indices(containing: 1) == [0, 1, 2]) // a zero-length interval contains its time stamp
        #expect(point.indices(overlapping: 3.5...4.5) == [0])
    }
    
    @Test
    func forEachIndexRethrows() {
        let tree = IntervalTree([Span(0, 4), Span(1, 4), Span(2, 4)])
        var visited: [Int] = []
        #expect(throws: StopError.self) {
            try tree.forEachIndex(overlapping: 3...3) { index in
                visited.append(index)
                if index == 1 { throw StopError() }
            }
        }
        #expect(visited == [0, 1])
    }
    
}
