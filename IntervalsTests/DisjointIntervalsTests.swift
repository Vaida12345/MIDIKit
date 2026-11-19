//
//  DisjointIntervalsTests.swift
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


/// Disjoint intervals over a slice, so that `startIndex` is not always `0`.
private struct Spans: DisjointIntervals {

    let base: ArraySlice<Span>

    var startIndex: Int { self.base.startIndex }
    var endIndex: Int { self.base.endIndex }

    subscript(position: Int) -> Span { self.base[position] }

    /// - Parameter padding: The number of placeholder elements before the intervals, which become the `startIndex`.
    init(_ spans: [Span], padding: Int = 0) {
        let full = Array(repeating: Span(-1, -1), count: padding) + spans
        self.base = full[padding...]
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


/// Random disjoint intervals on a quarter-beat grid, so that query time stamps often fall exactly on a bound.
private struct Figure {

    let spans: Spans

    /// Query time stamps covering the figure and a margin around it, on the quarter-beat grid.
    let queries: [Double]

    init(rng: inout TestRNG) {
        let count = rng.int(0...40)
        var time = 0.0
        var spans: [Span] = []
        for _ in 0..<count {
            time += Double(rng.int(0...3)) * 0.5 + 0.25 // gaps are at least a quarter, so neighbors never touch
            let duration = Double(rng.int(0...2)) * 0.25 // zero-length intervals included
            spans.append(Span(time, time + duration))
            time += duration
        }
        self.spans = Spans(spans, padding: rng.int(0...5))

        let end = Int(((spans.last?.offset ?? 1) + 1) * 4)
        self.queries = (-4...end).map { Double($0) / 4 }
    }

}


/// The linear-scan answers every query is checked against.
private enum Oracle {

    static func firstIndex(after t: Double, in spans: Spans) -> Int? {
        spans.indices.first { spans[$0].onset > t }
    }

    static func lastIndex(before t: Double, in spans: Spans) -> Int? {
        spans.indices.last { spans[$0].offset < t }
    }

    static func index(at t: Double, tolerance: Double, in spans: Spans) -> Int? {
        var best: (index: Int, distance: Double)? = nil
        for index in spans.indices {
            let span = spans[index]
            let distance = t < span.onset ? span.onset - t : (t > span.offset ? t - span.offset : 0)
            guard distance <= tolerance else { continue }
            if best == nil || distance < best!.distance { // strict, so the earlier wins a tie
                best = (index, distance)
            }
        }
        return best?.index
    }

    static func indices(overlapping range: ClosedRange<Double>, in spans: Spans) -> [Int] {
        spans.indices.filter { spans[$0].onset <= range.upperBound && spans[$0].offset >= range.lowerBound }
    }

}


// MARK: - Tests

@Suite
struct DisjointIntervalsTests {

    private static let tolerances: [Double] = [0, 0.125, 1]

    @Test
    func firstAndLast() {
        var rng = TestRNG(seed: 1)
        for _ in 0..<500 {
            let figure = Figure(rng: &rng)
            let spans = figure.spans
            for t in figure.queries {
                #expect(spans.firstIndex(after: t) == Oracle.firstIndex(after: t, in: spans))
                #expect(spans.first(after: t) == Oracle.firstIndex(after: t, in: spans).map { spans[$0] })
                #expect(spans.lastIndex(before: t) == Oracle.lastIndex(before: t, in: spans))
                #expect(spans.last(before: t) == Oracle.lastIndex(before: t, in: spans).map { spans[$0] })
            }
        }
    }

    @Test(arguments: tolerances)
    func indexAt(tolerance: Double) {
        var rng = TestRNG(seed: 2)
        for _ in 0..<500 {
            let figure = Figure(rng: &rng)
            let spans = figure.spans
            for t in figure.queries {
                #expect(spans.index(at: t, tolerance: tolerance) == Oracle.index(at: t, tolerance: tolerance, in: spans), "t: \(t)")
                if tolerance == 0 {
                    #expect(spans[at: t] == Oracle.index(at: t, tolerance: 0, in: spans).map { spans[$0] })
                }
            }
        }
    }

    @Test
    func overlapping() {
        var rng = TestRNG(seed: 3)
        for _ in 0..<500 {
            let figure = Figure(rng: &rng)
            let spans = figure.spans
            for _ in 0..<40 {
                let lower = figure.queries[rng.int(0...(figure.queries.count - 1))]
                let upper = lower + Double(rng.int(0...8)) / 4
                let expected = Oracle.indices(overlapping: lower...upper, in: spans)
                #expect(Array(spans.indices(overlapping: lower...upper)) == expected)
                #expect(spans.overlaps(with: Span(lower, upper)) == !expected.isEmpty)
            }
        }
    }

    /// Sweeps forward in time, with occasional backward jumps and arbitrary cursors.
    @Test
    func cursors() {
        var rng = TestRNG(seed: 4)
        for _ in 0..<500 {
            let figure = Figure(rng: &rng)
            let spans = figure.spans

            var firstCursor = spans.startIndex
            var lastCursor = spans.startIndex
            var atCursor = spans.startIndex
            var queryIndex = 0
            for _ in 0..<60 {
                if rng.int(0...4) == 0 {
                    queryIndex = rng.int(0...(figure.queries.count - 1)) // jump, often backward
                } else {
                    queryIndex = Swift.min(queryIndex + rng.int(0...6), figure.queries.count - 1)
                }
                if rng.int(0...6) == 0 {
                    firstCursor = rng.int(spans.startIndex...spans.endIndex)
                    lastCursor = rng.int(spans.startIndex...spans.endIndex)
                    atCursor = rng.int(spans.startIndex...spans.endIndex)
                }
                let t = figure.queries[queryIndex]

                firstCursor = spans.firstIndex(after: t, from: firstCursor)
                #expect(firstCursor == (Oracle.firstIndex(after: t, in: spans) ?? spans.endIndex))

                let last = spans.lastIndex(before: t, from: lastCursor)
                #expect(last == Oracle.lastIndex(before: t, in: spans))
                lastCursor = last ?? spans.startIndex

                let tolerance = Self.tolerances[rng.int(0...(Self.tolerances.count - 1))]
                let at = spans.index(at: t, tolerance: tolerance, from: atCursor)
                #expect(at == Oracle.index(at: t, tolerance: tolerance, in: spans), "t: \(t), tolerance: \(tolerance)")
                atCursor = at ?? atCursor
            }
        }
    }

    @Test
    func validity() {
        var rng = TestRNG(seed: 5)
        for _ in 0..<100 {
            #expect(Figure(rng: &rng).spans.isValidDisjointIntervals())
        }

        #expect(Spans([]).isValidDisjointIntervals())
        #expect(Spans([Span(1, 1)]).isValidDisjointIntervals())
        #expect(!Spans([Span(0, 2), Span(1, 3)]).isValidDisjointIntervals()) // overlapping
        #expect(!Spans([Span(0, 1), Span(1, 2)]).isValidDisjointIntervals()) // touching
        #expect(!Spans([Span(2, 1)]).isValidDisjointIntervals()) // inverted
    }

    @Test
    func edgeCases() {
        let empty = Spans([], padding: 3)
        #expect(empty.firstIndex(after: 0) == nil)
        #expect(empty.firstIndex(after: 0, from: empty.startIndex) == empty.endIndex)
        #expect(empty.lastIndex(before: 0) == nil)
        #expect(empty.index(at: 0, tolerance: .infinity) == nil)
        #expect(empty.indices(overlapping: 0...1).isEmpty)

        let spans = Spans([Span(1, 2), Span(4, 5)], padding: 2)
        #expect(spans.firstIndex(after: 1) == 3) // starting exactly at the time stamp is not after it
        #expect(spans.lastIndex(before: 2) == nil) // ending exactly at the time stamp is not before it
        #expect(spans.index(at: 1) == 2)
        #expect(spans.index(at: 2) == 2)
        #expect(spans.index(at: 3) == nil)
        #expect(spans.index(at: 3, tolerance: 1) == 2) // equally close to both, the earlier wins
        #expect(spans.index(at: 3.5, tolerance: 1) == 3) // closer to the later one
        #expect(spans.indices(overlapping: 2...4) == 2..<4) // touching bounds overlap
        #expect(!spans.overlaps(with: Span(2.5, 3.5)))
    }

}
