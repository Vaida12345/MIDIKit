//
//  RegionTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing


@Suite("IndexedContainer.Regions")
struct RegionTests {

    private func makeIndexed(_ notes: [MIDINote], sustains: [MIDISustainEvent] = []) -> IndexedContainer {
        let track = MIDITrack(notes: notes, sustains: sustains)
        return MIDIContainer(tracks: [track]).indexed()
    }

    @Test func emptyContainerReturnsNoRegions() {
        let indexed = MIDIContainer().indexed()
        #expect(indexed.regions().isEmpty)
    }

    @Test func noSustainReturnsSingleRegion() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 64, velocity: 80),
        ])
        let regions = indexed.regions()
        #expect(regions.count == 1)
        #expect(regions[0].notes.count == 2)
    }

    @Test func sustainsCreateRegions() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 5, offset: 6, note: 64, velocity: 80),
        ], sustains: [
            MIDISustainEvent(onset: 0, offset: 3),
            MIDISustainEvent(onset: 4, offset: 7),
        ])
        let regions = indexed.regions()
        #expect(!regions.isEmpty)
    }

    @Test func regionsSorted() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 64, velocity: 80),
            MIDINote(onset: 4, offset: 5, note: 67, velocity: 90),
        ])
        let regions = indexed.regions()
        for i in 1..<regions.count {
            #expect(regions[i - 1].onset <= regions[i].onset)
        }
    }

    @Test func regionHasMinMaxFromNotes() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 3, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 5, note: 64, velocity: 80),
        ])
        let regions = indexed.regions()
        if let region = regions.first {
            #expect(region.onset == 1.0)
            #expect(region.offset == 5.0)
        }
    }

    @Test func regionsAreSortedByOnset() {
        let indexed = makeIndexed([
            MIDINote(onset: 3, offset: 4, note: 60, velocity: 100),
            MIDINote(onset: 0, offset: 1, note: 64, velocity: 80),
            MIDINote(onset: 1.5, offset: 2, note: 67, velocity: 90),
        ])
        let regions = indexed.regions()
        for i in 1..<regions.count {
            #expect(regions[i - 1].onset <= regions[i].onset)
        }
    }

}
