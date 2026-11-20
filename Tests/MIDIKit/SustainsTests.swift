//
//  SustainsTests.swift
//  MIDIKit
//

import MIDIKit
import Intervals
import Testing


@Suite("MIDISustainEvent")
struct MIDISustainEventTests {

    @Test func basicInit() {
        let sustain = MIDISustainEvent(onset: 1.0, offset: 3.0)
        #expect(sustain.onset == 1.0)
        #expect(sustain.offset == 3.0)
    }

    @Test func durationGetter() {
        let sustain = MIDISustainEvent(onset: 1.0, offset: 4.0)
        #expect(sustain.duration == 3.0)
    }

    @Test func durationSetterChangesOffset() {
        var sustain = MIDISustainEvent(onset: 1.0, offset: 3.0)
        sustain.duration = 5.0
        #expect(sustain.offset == 6.0)
        #expect(sustain.onset == 1.0)
    }

    @Test func equatable() {
        let a = MIDISustainEvent(onset: 1.0, offset: 2.0)
        let b = MIDISustainEvent(onset: 1.0, offset: 2.0)
        #expect(a == b)
    }

    @Test func notEqualDifferentValues() {
        let a = MIDISustainEvent(onset: 1.0, offset: 2.0)
        let b = MIDISustainEvent(onset: 1.0, offset: 3.0)
        #expect(a != b)
    }

    @Test func hashable() {
        let a = MIDISustainEvent(onset: 1.0, offset: 2.0)
        let b = MIDISustainEvent(onset: 1.0, offset: 2.0)
        #expect(a.hashValue == b.hashValue)
    }

}


@Suite("MIDISustainEvents")
struct MIDISustainEventsTests {

    @Test func initEmpty() {
        let sustains = MIDISustainEvents()
        #expect(sustains.isEmpty)
        #expect(sustains.count == 0)
    }

    @Test func initSortsByOnset() {
        let sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 3.0, offset: 4.0),
            MIDISustainEvent(onset: 1.0, offset: 2.0),
            MIDISustainEvent(onset: 2.0, offset: 3.0),
        ])
        #expect(sustains[0].onset == 1.0)
        #expect(sustains[1].onset == 2.0)
        #expect(sustains[2].onset == 3.0)
    }

    @Test func insertSingle() {
        var sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 1.0, offset: 2.0),
            MIDISustainEvent(onset: 4.0, offset: 5.0),
        ])
        sustains.insert(MIDISustainEvent(onset: 2.5, offset: 3.0))
        #expect(sustains.count == 3)
        #expect(sustains[0].onset == 1.0)
        #expect(sustains[1].onset == 2.5)
        #expect(sustains[2].onset == 4.0)
    }

    @Test func insertAtBeginning() {
        var sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 2.0, offset: 3.0),
        ])
        sustains.insert(MIDISustainEvent(onset: 0.0, offset: 1.0))
        #expect(sustains[0].onset == 0.0)
        #expect(sustains[1].onset == 2.0)
    }

    @Test func insertAtEnd() {
        var sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 1.0, offset: 2.0),
        ])
        sustains.insert(MIDISustainEvent(onset: 5.0, offset: 6.0))
        #expect(sustains[1].onset == 5.0)
    }

    @Test func insertContentsOf() {
        var sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 1.0, offset: 2.0),
        ])
        sustains.insert(contentsOf: MIDISustainEvents([
            MIDISustainEvent(onset: 0.5, offset: 0.8),
            MIDISustainEvent(onset: 3.0, offset: 4.0),
        ]))
        #expect(sustains.count == 3)
        #expect(sustains[0].onset == 0.5)
        #expect(sustains[1].onset == 1.0)
        #expect(sustains[2].onset == 3.0)
    }

    @Test func iteration() {
        let sustains = MIDISustainEvents([
            MIDISustainEvent(onset: 1.0, offset: 2.0),
            MIDISustainEvent(onset: 3.0, offset: 4.0),
        ])
        var collected: [MIDISustainEvent] = []
        for s in sustains {
            collected.append(s)
        }
        #expect(collected.count == 2)
    }

    @Test func insertKeepsOrder() {
        var sustains = MIDISustainEvents([MIDISustainEvent(onset: 1, offset: 3)])
        sustains.insert(MIDISustainEvent(onset: 6, offset: 7))
        #expect(sustains.contents == [.init(onset: 1, offset: 3), .init(onset: 6, offset: 7)])
        sustains.insert(MIDISustainEvent(onset: 4, offset: 5))
        #expect(sustains.contents == [.init(onset: 1, offset: 3), .init(onset: 4, offset: 5), .init(onset: 6, offset: 7)])
        sustains.insert(MIDISustainEvent(onset: 0, offset: 0.5))
        #expect(sustains.contents == [.init(onset: 0, offset: 0.5), .init(onset: 1, offset: 3), .init(onset: 4, offset: 5), .init(onset: 6, offset: 7)])
    }

    @Test func equatable() {
        let a = MIDISustainEvents([MIDISustainEvent(onset: 1, offset: 2)])
        let b = MIDISustainEvents([MIDISustainEvent(onset: 1, offset: 2)])
        #expect(a == b)
    }

    // MARK: A gap at every pedal change

    private static let gap = 1.0 / 128

    private static func sustains(_ ranges: (Double, Double)...) -> [MIDISustainEvent] {
        ranges.map { MIDISustainEvent(onset: $0.0, offset: $0.1) }
    }

    @Test func touchingSustainsStayApart() {
        let gap = Self.gap
        #expect(MIDISustainEvents(Self.sustains((1, 2), (0, 1))).contents == Self.sustains((0, 1 - gap), (1, 2)))
    }

    @Test func nearlyTouchingSustainsGetTheFullGap() {
        let gap = Self.gap
        let onset = 1 + gap / 2
        #expect(MIDISustainEvents(Self.sustains((0, 1), (onset, 2))).contents == Self.sustains((0, onset - gap), (onset, 2)))
    }

    @Test func overlappingSustainsSplitAtTheLaterOnset() {
        let gap = Self.gap
        #expect(MIDISustainEvents(Self.sustains((0, 2), (1, 3))).contents == Self.sustains((0, 1 - gap), (1, 3)))
    }

    /// A sustain inside another splits it, and the pedal stays down until the end of the outer one.
    @Test func aContainedSustainSplitsTheOuterOne() {
        let gap = Self.gap
        #expect(MIDISustainEvents(Self.sustains((0, 4), (1, 2))).contents == Self.sustains((0, 1 - gap), (1, 4)))
    }

    /// Onsets closer than the gap are the same pedal change.
    @Test func onsetsWithinTheGapMerge() {
        let gap = Self.gap
        #expect(MIDISustainEvents(Self.sustains((0, 1), (gap / 2, 3))).contents == Self.sustains((0, 3)))
        #expect(MIDISustainEvents(Self.sustains((0, 2), (0, 1))).contents == Self.sustains((0, 2)))
    }

    @Test func sustainsFarApartAreKept() {
        let sustains = Self.sustains((0, 1), (1.5, 2), (2.5, 2.5))
        #expect(MIDISustainEvents(sustains).contents == sustains)
    }

    @Test func invalidSustainsAreDropped() {
        let sustains = MIDISustainEvents(Self.sustains((0, 1), (3, 2), (.nan, 4), (5, .infinity), (-.infinity, 6)))
        #expect(sustains.contents == Self.sustains((0, 1)))
    }

    /// A gap under two ticks of the write grid is raised to two ticks, so no sustain is lost in a file.
    @Test func aGapUnderTwoTicksIsRaised() throws {
        let tick = 1 / Double(MIDIContainer.writeResolution)
        func written(_ sustains: MIDISustainEvents) throws -> MIDISustainEvents {
            try MIDIContainer(data: MIDIContainer(tracks: [MIDITrack(notes: [], sustains: sustains)]).data()).tracks[0].sustains
        }

        // Onsets closer than two ticks are one pedal change.
        let close = MIDISustainEvents(Self.sustains((1, 1.00001), (1.00002, 2)), minimumGap: 1e-5)
        #expect(close.contents == Self.sustains((1, 2)))
        #expect(try written(close).contents == Self.sustains((1, 2)))

        // Further apart, the pedal is up for two ticks. Reading cleans up with the default gap of 1/128, which merges this pedal change, but the pedal is down as long as before: no part of it is lost.
        let apart = MIDISustainEvents(Self.sustains((1, 1.0001), (1.0003, 2)), minimumGap: 1e-5)
        #expect(apart.contents == Self.sustains((1, 1.0003 - 2 * tick), (1.0003, 2)))
        #expect(try written(apart).contents == Self.sustains((1, 2)))
    }

    @Test func customGap() {
        #expect(MIDISustainEvents(Self.sustains((0, 1), (1, 2)), minimumGap: 1 / 16).contents == Self.sustains((0, 1 - 1 / 16), (1, 2)))
    }

    @Test func insertSplitsAtThePedalChange() {
        let gap = Self.gap
        var sustains = MIDISustainEvents(Self.sustains((0, 1), (3, 4)))
        sustains.insert(MIDISustainEvent(onset: 1, offset: 2))
        #expect(sustains.contents == Self.sustains((0, 1 - gap), (1, 2), (3, 4)))
        sustains.insert(MIDISustainEvent(onset: 3.5, offset: 5))
        #expect(sustains.contents == Self.sustains((0, 1 - gap), (1, 2), (3, 3.5 - gap), (3.5, 5)))
        sustains.insert(MIDISustainEvent(onset: 6, offset: 5)) // ends before it starts
        #expect(sustains.count == 4)
    }

    @Test func insertContentsOfSplitsAtThePedalChange() {
        let gap = Self.gap
        var sustains = MIDISustainEvents(Self.sustains((0, 2), (5, 6)))
        sustains.insert(contentsOf: MIDISustainEvents(Self.sustains((1, 3), (6, 7))))
        #expect(sustains.contents == Self.sustains((0, 1 - gap), (1, 3), (5, 6 - gap), (6, 7)))
    }

    /// On random sustains, the result is sorted and disjoint with the gap, starts only where a source sustain starts, and covers only what the sources cover.
    @Test(arguments: 0..<20)
    func randomSustains(seed: Int) {
        var rng = IndexedTrackRNG(seed: UInt64(seed) &+ 9_000)
        let source = (0..<rng.int(0...40)).map { _ in
            let onset = Double(rng.int(0...640)) / 64 + (rng.int(0...3) == 0 ? Double(rng.int(0...100)) / 100_000 : 0)
            return MIDISustainEvent(onset: onset, offset: onset + Double(rng.int(0...128)) / 64)
        }
        let sustains = MIDISustainEvents(source)

        #expect(sustains.isValidDisjointIntervals())
        for index in sustains.indices.dropFirst() {
            #expect(sustains[index].onset - sustains[index - 1].offset >= Self.gap - 1e-12)
        }
        for sustain in sustains {
            #expect(source.contains { $0.onset == sustain.onset })
            for time in [sustain.onset, (sustain.onset + sustain.offset) / 2, sustain.offset] {
                #expect(source.contains { $0.onset <= time && time <= $0.offset })
            }
        }
    }

    /// Transforms that keep the sustains disjoint keep their spacing, and others clean them up.
    @Test func transformsKeepTheSpacing() {
        let sustains = MIDISustainEvents(Self.sustains((0, 1), (1.001, 2)), minimumGap: 1 / 1024)
        let scaled = sustains.transformed { MIDISustainEvent(onset: $0.onset * 2, offset: $0.offset * 2) }
        #expect(scaled.contents == Self.sustains((0, 2), (2.002, 4)))

        let collapsed = sustains.transformed { _ in MIDISustainEvent(onset: 0, offset: 1) }
        #expect(collapsed.contents == Self.sustains((0, 1)))
    }

}
