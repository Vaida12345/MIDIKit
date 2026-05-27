//
//  AlignAndNormalizeTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing


@Suite("IndexedContainer.AlignFirstNote")
struct AlignFirstNoteTests {

    private func makeIndexed(_ notes: [MIDINote], sustains: [MIDISustainEvent] = []) -> IndexedContainer {
        let track = MIDITrack(notes: notes, sustains: sustains)
        return MIDIContainer(tracks: [track]).indexed()
    }

    @Test func alignShiftsNotesToZero() {
        let indexed = makeIndexed([
            MIDINote(onset: 5, offset: 6, note: 60, velocity: 100),
            MIDINote(onset: 7, offset: 8, note: 64, velocity: 80),
        ])
        indexed.alignFirstNoteToZero()
        #expect(indexed.contents[0].onset == 0)
        #expect(indexed.contents[1].onset == 2)
    }

    @Test func alignShiftsSustains() {
        let indexed = makeIndexed([
            MIDINote(onset: 5, offset: 10, note: 60, velocity: 100),
        ], sustains: [
            MIDISustainEvent(onset: 5, offset: 6),
            MIDISustainEvent(onset: 7, offset: 10),
        ])
        indexed.alignFirstNoteToZero()
        #expect(indexed.sustains[0].onset == 0)
        #expect(indexed.sustains[0].offset == 1)
        #expect(indexed.sustains[1].onset == 2)
        #expect(indexed.sustains[1].offset == 5)
    }

    @Test func alignRemovesNegativeSustains() {
        let indexed = makeIndexed([
            MIDINote(onset: 5, offset: 10, note: 60, velocity: 100),
        ], sustains: [
            MIDISustainEvent(onset: 3, offset: 4), // before first note — will become negative
            MIDISustainEvent(onset: 7, offset: 10),
        ])
        indexed.alignFirstNoteToZero()
        // Negative-onset sustain should be removed
        for sustain in indexed.sustains {
            #expect(sustain.onset >= 0)
        }
    }

    @Test func alignEmptyContainer() {
        let indexed = MIDIContainer().indexed()
        indexed.alignFirstNoteToZero()
        #expect(indexed.isEmpty) // no crash
    }

}


@Suite("IndexedContainer.Normalize")
struct NormalizeTests {

    private func makeIndexed(_ notes: [MIDINote], sustains: [MIDISustainEvent] = []) -> IndexedContainer {
        let track = MIDITrack(notes: notes, sustains: sustains)
        return MIDIContainer(tracks: [track]).indexed()
    }

    @Test func normalizeEmptyDoesNotCrash() {
        let indexed = MIDIContainer().indexed()
        indexed.normalize(preserve: .acousticResult)
        // no crash
    }

    @Test func normalizeSingleNote() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
        ])
        indexed.normalize(preserve: .acousticResult)
        #expect(!indexed.isEmpty)
    }

    @Test func normalizeWithSustains() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 2, note: 60, velocity: 100),
            MIDINote(onset: 3, offset: 5, note: 64, velocity: 80),
        ], sustains: [
            MIDISustainEvent(onset: 0, offset: 2),
            MIDISustainEvent(onset: 3, offset: 5),
        ])
        indexed.normalize(preserve: .acousticResult)
        // Notes should be adjusted to not overlap
        #expect(indexed.count >= 1)
    }

    @Test func normalizePreserveAcoustic() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 3, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 5, note: 64, velocity: 80),
        ])
        indexed.normalize(preserve: .acousticResult)
        // Should complete without error
    }

    @Test func normalizePreserveNotesDisplay() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 3, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 5, note: 64, velocity: 80),
        ])
        indexed.normalize(preserve: .notesDisplay)
        // Should complete without error
    }

    @Test func preserveSettingsAllCases() {
        let all = IndexedContainer.PreserveSettings.allCases
        #expect(all.contains(.acousticResult))
        #expect(all.contains(.notesDisplay))
    }

}
