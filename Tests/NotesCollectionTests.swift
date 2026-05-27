//
//  NotesCollectionTests.swift
//  MIDIKit
//

import Testing
import MIDIKit


@Suite("MIDINotes")
struct MIDINotesTests {

    @Test func initEmpty() {
        let notes = MIDINotes([])
        #expect(notes.isEmpty)
        #expect(notes.count == 0)
    }

    @Test func initWithContents() {
        let note1 = MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)
        let note2 = MIDINote(onset: 2, offset: 3, note: 64, velocity: 80)
        let notes = MIDINotes([note1, note2])
        #expect(notes.count == 2)
        #expect(notes[0] == note1)
        #expect(notes[1] == note2)
    }

    @Test func appendSingleNote() {
        var notes = MIDINotes([])
        let note = MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)
        notes.append(note)
        #expect(notes.count == 1)
        #expect(notes[0] == note)
    }

    @Test func appendContents() {
        var notes = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let more = MIDINotes([MIDINote(onset: 2, offset: 3, note: 64, velocity: 80)])
        notes.append(contentsOf: more)
        #expect(notes.count == 2)
    }

    @Test func noteRange() {
        let notes = MIDINotes([
            MIDINote(onset: 0, offset: 1, note: 40, velocity: 100),
            MIDINote(onset: 1, offset: 2, note: 72, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 55, velocity: 100),
        ])
        let range = notes.noteRange()
        #expect(range?.min == 40)
        #expect(range?.max == 72)
    }

    @Test func noteRangeEmpty() {
        let notes = MIDINotes([])
        #expect(notes.noteRange() == nil)
    }

    @Test func noteRangeSingleNote() {
        let notes = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let range = notes.noteRange()
        #expect(range?.min == 60)
        #expect(range?.max == 60)
    }

    @Test func sortOrdersByOnset() {
        var notes = MIDINotes([
            MIDINote(onset: 3, offset: 4, note: 60, velocity: 100),
            MIDINote(onset: 1, offset: 2, note: 64, velocity: 80),
            MIDINote(onset: 2, offset: 3, note: 67, velocity: 90),
        ])
        notes.sort()
        #expect(notes[0].onset == 1)
        #expect(notes[1].onset == 2)
        #expect(notes[2].onset == 3)
    }

    @Test func sequenceIteration() {
        let notes = MIDINotes([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 1, offset: 2, note: 64, velocity: 80),
        ])
        var collected: [MIDINote] = []
        for note in notes {
            collected.append(note)
        }
        #expect(collected.count == 2)
    }

    @Test func equatable() {
        let a = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let b = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        #expect(a == b)
    }

    @Test func notEqualDifferentCounts() {
        let a = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let b = MIDINotes([])
        #expect(a != b)
    }

    @Test func arrayLiteralInit() {
        let notes: MIDINotes = [
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 1, offset: 2, note: 64, velocity: 80),
        ]
        #expect(notes.count == 2)
    }

}


@Suite("MIDINotes.deriveReferenceNoteLength")
struct DeriveReferenceNoteLengthTests {

    @Test func emptyReturnsZero() {
        let notes = MIDINotes([])
        #expect(notes.deriveReferenceNoteLength() == 0)
    }

    @Test func singleNoteReturnsZero() {
        let notes = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        #expect(notes.deriveReferenceNoteLength() == 0)
    }

    @Test func regularQuarterNotes() {
        // Quarter notes at 120 BPM: each onset is 1.0 apart
        var notesArray: [MIDINote] = []
        for i in 0..<16 {
            notesArray.append(MIDINote(onset: Double(i), offset: Double(i) + 0.5, note: 60, velocity: 100))
        }
        let notes = MIDINotes(notesArray)
        let refLen = notes.deriveReferenceNoteLength()
        // Should identify ~1.0 as the reference note length
        #expect(refLen > 0)
        #expect(refLen < 2.0)
    }

    @Test func eighthNotes() {
        var notesArray: [MIDINote] = []
        for i in 0..<32 {
            notesArray.append(MIDINote(onset: Double(i) * 0.5, offset: Double(i) * 0.5 + 0.25, note: 60, velocity: 100))
        }
        let notes = MIDINotes(notesArray)
        let refLen = notes.deriveReferenceNoteLength()
        #expect(refLen > 0)
        #expect(refLen < 1.0)
    }

    @Test func respectMinimumNoteDistance() {
        // Two notes that form a chord (very close together) should be filtered
        let notes = MIDINotes([
            MIDINote(onset: 0.0, offset: 0.5, note: 60, velocity: 100),
            MIDINote(onset: 0.01, offset: 0.5, note: 64, velocity: 80), // chord — filtered
            MIDINote(onset: 1.0, offset: 1.5, note: 60, velocity: 100),
            MIDINote(onset: 1.01, offset: 1.5, note: 64, velocity: 80), // chord — filtered
            MIDINote(onset: 2.0, offset: 2.5, note: 60, velocity: 100),
        ])
        let refLen = notes.deriveReferenceNoteLength(minimumNoteDistance: 0.1)
        #expect(refLen > 0)
    }

}
