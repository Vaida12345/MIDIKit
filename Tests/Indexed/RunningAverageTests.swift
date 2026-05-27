//
//  RunningAverageTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing


@Suite("RunningAverage")
struct RunningAverageTests {

    private func makeIndexed(_ notes: [MIDINote]) -> IndexedContainer {
        let track = MIDITrack(notes: notes)
        return MIDIContainer(tracks: [track]).indexed()
    }

    @Test func emptyContainer() {
        let indexed = MIDIContainer().indexed()
        let avg = indexed.runningAverage()
        #expect(avg[at: 0] == nil)
    }

    @Test func singleNote() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 2, note: 60, velocity: 100),
        ])
        let avg = indexed.runningAverage()
        let element = avg[at: 1]
        #expect(element != nil)
        #expect(element?.note == 60)
    }

    @Test func twoNotesSamePitch() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 2, note: 60, velocity: 100),
            MIDINote(onset: 3, offset: 4, note: 60, velocity: 80),
        ])
        let avg = indexed.runningAverage()
        // At time 1, average should include the first note
        let at1 = avg[at: 1]
        #expect(at1 != nil)
        // At time 3, average should include both notes
        let at3 = avg[at: 3]
        #expect(at3 != nil)
    }

    @Test func wideSpanNotes() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 2, note: 40, velocity: 100),
            MIDINote(onset: 1, offset: 2, note: 80, velocity: 100),
        ])
        let avg = indexed.runningAverage()
        let element = avg[at: 1]
        #expect(element != nil)
        // midpoint between 40 and 80 is 60
        #expect(element?.note == 60)
        #expect(element?.span == 40)
    }

    @Test func binarySearchBeforeFirst() {
        let indexed = makeIndexed([
            MIDINote(onset: 5, offset: 6, note: 60, velocity: 100),
        ])
        let avg = indexed.runningAverage()
        // Query before first element
        let element = avg[at: 0]
        // Should return the nearest (first) element
        #expect(element != nil)
    }

    @Test func binarySearchAfterLast() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 2, note: 60, velocity: 100),
        ])
        let avg = indexed.runningAverage()
        let element = avg[at: 100]
        // Should return the nearest (last) element
        #expect(element != nil)
    }

    @Test func exactMatch() {
        let indexed = makeIndexed([
            MIDINote(onset: 1.0, offset: 2.0, note: 60, velocity: 100),
            MIDINote(onset: 3.0, offset: 4.0, note: 64, velocity: 80),
        ])
        let avg = indexed.runningAverage()
        let element = avg[at: 1.0]
        #expect(element?.onset == 1.0)
    }

    @Test func runningLengthLimitsWindow() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 30, velocity: 100),
            MIDINote(onset: 10, offset: 11, note: 80, velocity: 100),
        ])
        // With running length 1, the notes shouldn't affect each other (too far apart)
        let avg = indexed.runningAverage(runningLength: 1)
        let at0 = avg[at: 0]
        let at10 = avg[at: 10]
        // Each should have its own isolated note range
        #expect(at0 != nil)
        #expect(at10 != nil)
    }

}
