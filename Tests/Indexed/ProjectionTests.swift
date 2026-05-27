//
//  ProjectionTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing


@Suite("TimeWarpMapping")
struct TimeWarpMappingTests {

    @Test func identityMapping() {
        let identity = IndexedContainer.TimeWarpMapping.identity
        #expect(identity.map(0) == 0)
        #expect(identity.map(5) == 5)
        #expect(identity.map(100) == 100)
    }

    @Test func linearMapping() {
        let warp = IndexedContainer.TimeWarpMapping(xs: [0, 10], ys: [0, 20], fallbackSlope: 2)
        #expect(warp.map(5) == 10)
        #expect(warp.map(10) == 20)
    }

    @Test func extrapolationBeforeFirstKnot() {
        let warp = IndexedContainer.TimeWarpMapping(xs: [2, 4], ys: [4, 8], fallbackSlope: 2)
        // slope = (8-4)/(4-2) = 2
        // map(0) = 4 + 2 * (0 - 2) = 4 - 4 = 0
        #expect(abs(warp.map(0) - 0) < 1e-9)
    }

    @Test func extrapolationAfterLastKnot() {
        let warp = IndexedContainer.TimeWarpMapping(xs: [0, 2], ys: [0, 4], fallbackSlope: 2)
        // slope = (4-0)/(2-0) = 2
        // map(3) = 4 + 2 * (3 - 2) = 6
        #expect(abs(warp.map(3) - 6) < 1e-9)
    }

    @Test func singleKnot() {
        let warp = IndexedContainer.TimeWarpMapping(xs: [5], ys: [10], fallbackSlope: 1)
        #expect(warp.map(6) == 11) // 10 + 1 * (6 - 5)
    }

    @Test func emptyMappingUsesIdentity() {
        let warp = IndexedContainer.TimeWarpMapping(xs: [], ys: [], fallbackSlope: 1)
        #expect(warp.map(42) == 42)
    }

    @Test func interpolationBetweenKnots() {
        let warp = IndexedContainer.TimeWarpMapping(xs: [0, 2, 4], ys: [0, 10, 20])
        #expect(warp.map(1) == 5)
        #expect(warp.map(3) == 15)
    }

}


@Suite("IndexedContainer.Projection")
struct ProjectionTests {

    private func makeIndexed(_ notes: [MIDINote], sustains: [MIDISustainEvent] = []) -> IndexedContainer {
        let track = MIDITrack(notes: notes, sustains: sustains)
        return MIDIContainer(tracks: [track]).indexed()
    }

    @Test func identityProjectionPreservesNotes() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 64, velocity: 80),
        ])
        indexed.projection(.identity)
        #expect(indexed.contents[0].onset == 0)
        #expect(indexed.contents[1].onset == 2)
    }

    @Test func linearScalingProjection() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 64, velocity: 80),
        ])
        // Scale time by factor 2
        let warp = IndexedContainer.TimeWarpMapping(xs: [0, 1], ys: [0, 2], fallbackSlope: 2)
        indexed.projection(warp)
        #expect(indexed.contents[0].onset == 0)
        #expect(indexed.contents[1].onset == 4) // 2 → mapped: 4
    }

    @Test func projectionPreservesDurations() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 2, note: 60, velocity: 100),
        ])
        let warp = IndexedContainer.TimeWarpMapping(xs: [0, 2], ys: [0, 4], fallbackSlope: 2)
        indexed.projection(warp)
        // Onset remapped, duration preserved
        #expect(indexed.contents[0].duration == 1.0)
    }

    @Test func projectionShiftsSustains() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 2, note: 60, velocity: 100),
        ], sustains: [
            MIDISustainEvent(onset: 1, offset: 2),
        ])
        let warp = IndexedContainer.TimeWarpMapping(xs: [0, 2], ys: [0, 4], fallbackSlope: 2)
        indexed.projection(warp)
        #expect(indexed.sustains[0].duration == 1.0)
    }

    @Test func projectionEmptyContainer() {
        let indexed = MIDIContainer().indexed()
        indexed.projection(.identity)
        #expect(indexed.isEmpty)
    }

}


@Suite("TimeWarp")
struct TimeWarpTests {

    private func makeIndexed(_ notes: [MIDINote]) -> IndexedContainer {
        let track = MIDITrack(notes: notes)
        return MIDIContainer(tracks: [track]).indexed()
    }

    @Test func emptyProducesIdentityMapping() {
        let a = MIDIContainer().indexed()
        let b = MIDIContainer().indexed()
        let warp = a.timeWarp(other: b)
        #expect(warp.map(5) == 5) // identity fallback
    }

    @Test func singleNoteEach() {
        let a = makeIndexed([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let b = makeIndexed([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let warp = a.timeWarp(other: b)
        #expect(warp.map(0) >= 0) // should return a valid mapping
    }

    @Test func timeWarpRobustness() {
        // Generate some notes for each container
        var notesA: [MIDINote] = []
        var notesB: [MIDINote] = []
        for i in 0..<10 {
            notesA.append(MIDINote(onset: Double(i), offset: Double(i) + 0.5, note: 60 + UInt8(i % 7), velocity: 100))
            notesB.append(MIDINote(onset: Double(i) * 1.1, offset: Double(i) * 1.1 + 0.5, note: 60 + UInt8(i % 7), velocity: 100))
        }
        let a = makeIndexed(notesA)
        let b = makeIndexed(notesB)
        let warp = a.timeWarp(other: b)
        // The mapping should be monotonic
        #expect(warp.map(0) <= warp.map(5))
    }

    @Test func timeWarpParametersDefaultInit() {
        let params = IndexedContainer.TimeWarpParameters()
        #expect(params.tauDice1 == 0.50)
        #expect(params.tauDice2 == 0.34)
        #expect(params.overlapReward == 2.0)
        #expect(params.mismatchPenalty == 0.8)
        #expect(params.gapOpen == 2.5)
        #expect(params.gapExtend == 0.5)
        #expect(params.timingWeight == 1.5)
        #expect(params.slopeMin == 0.05)
        #expect(params.slopeMax == 20.0)
    }

    @Test func medianAbsoluteDeviation() {
        let values = [1.0, 2.0, 3.0, 4.0, 100.0]
        let mad = IndexedContainer.medianAbsoluteDeviation(values)
        #expect(mad != nil)
        #expect(mad! > 0)
    }

    @Test func medianAbsoluteDeviationEmpty() {
        #expect(IndexedContainer.medianAbsoluteDeviation([]) == nil)
    }

    @Test func medianAbsoluteDeviationSingle() {
        #expect(IndexedContainer.medianAbsoluteDeviation([5.0]) == 0.0)
    }

}
