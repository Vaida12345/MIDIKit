//
//  IndexedContainerTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing


@Suite("IndexedContainer")
struct IndexedContainerTests {

    @Test func initEmpty() {
        let container = MIDIContainer()
        let indexed = container.indexed()
        #expect(indexed.isEmpty)
        #expect(indexed.count == 0)
    }

    @Test func initWithNotes() {
        let notes = MIDINotes([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 64, velocity: 80),
        ])
        let container = MIDIContainer(notes: notes)
        let indexed = container.indexed()
        #expect(!indexed.isEmpty)
        #expect(indexed.count == 2)
    }

    @Test func makeContainerRoundtrip() {
        let notes = MIDINotes([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 64, velocity: 80),
        ])
        let original = MIDIContainer(notes: notes)
        let indexed = original.indexed()
        let roundtripped = indexed.makeContainer()
        #expect(roundtripped.tracks.count == 1)
        #expect(roundtripped.tracks[0].notes.count == 2)
        // Notes should be sorted by onset
        #expect(roundtripped.tracks[0].notes[0].onset == 0)
        #expect(roundtripped.tracks[0].notes[1].onset == 2)
    }

    @Test func sustainsPreserved() {
        let notes = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let sustains = MIDISustainEvents([MIDISustainEvent(onset: 0, offset: 2)])
        let container = MIDIContainer(notes: notes, sustains: sustains)
        let indexed = container.indexed()
        #expect(indexed.sustains.count == 1)
        let result = indexed.makeContainer()
        #expect(result.tracks[0].sustains.count == 1)
    }

    @Test func notesGroupedByPitch() {
        let notes = MIDINotes([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 60, velocity: 80),
            MIDINote(onset: 1, offset: 2, note: 64, velocity: 90),
        ])
        let container = MIDIContainer(notes: notes)
        let indexed = container.indexed()
        #expect(indexed.notes[60]?.count == 2)
        #expect(indexed.notes[64]?.count == 1)
    }

    @Test func sequenceIteration() {
        let notes = MIDINotes([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 1, offset: 2, note: 64, velocity: 80),
        ])
        let container = MIDIContainer(notes: notes)
        let indexed = container.indexed()
        var collected: [MIDINote] = []
        for ref in indexed {
            collected.append(ref.pointee)
        }
        #expect(collected.count == 2)
    }

    @Test func iteratorExhaustion() {
        let container = MIDIContainer(notes: MIDINotes([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
        ]))
        let indexed = container.indexed()
        var iterator = indexed.makeIterator()
        #expect(iterator.next() != nil)
        #expect(iterator.next() == nil)
        #expect(iterator.next() == nil) // should continue returning nil
    }

    @Test func multipleTracksMergeNotes() {
        let track1 = MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let track2 = MIDITrack(notes: [MIDINote(onset: 2, offset: 3, note: 64, velocity: 80)])
        let container = MIDIContainer(tracks: [track1, track2])
        let indexed = container.indexed()

        // Multi-track notes are merged into a single indexed container
        // Each track's notes get channel encoding
        #expect(indexed.count == 2)
        let result = indexed.makeContainer()
        #expect(result.tracks[0].notes.count == 2)
    }

    @Test func minimumGapEnforcement() {
        let notes = MIDINotes([
            MIDINote(onset: 0.0, offset: 0.5, note: 60, velocity: 100),
            MIDINote(onset: 0.51, offset: 1.0, note: 60, velocity: 80),
        ])
        let container = MIDIContainer(notes: notes)
        let indexedWithGap = container.indexed(minimumConsecutiveNotesGap: 0.1)
        let result = indexedWithGap.makeContainer()
        #expect(result.tracks[0].notes.count == 2)
        // Notes should be adjusted to not overlap
        for i in 0..<(result.tracks[0].notes.count - 1) {
            #expect(result.tracks[0].notes[i].offset <= result.tracks[0].notes[i + 1].onset)
        }
    }

}
