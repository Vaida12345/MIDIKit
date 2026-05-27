//
//  ChordTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing


@Suite("Chord")
struct ChordTests {

    private func makeIndexed(_ notes: [MIDINote]) -> IndexedContainer {
        let track = MIDITrack(notes: notes)
        return MIDIContainer(tracks: [track]).indexed()
    }

    @Test func chordsEmptyContainer() {
        let indexed = MIDIContainer().indexed()
        let chords = indexed.chords()
        #expect(chords.isEmpty)
    }

    @Test func singleNoteSingleChord() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
        ])
        let chords = indexed.chords()
        #expect(chords.count == 1)
        #expect(chords[0].count == 1)
    }

    @Test func chordGroupsSimultaneousNotes() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 0.02, offset: 1, note: 64, velocity: 80),
            MIDINote(onset: 0.04, offset: 1, note: 67, velocity: 90), // C major triad
        ])
        let chords = indexed.chords()
        // All three should be in the same chord (within default 0.1 duration threshold)
        #expect(chords.count == 1)
        #expect(chords[0].count == 3)
    }

    @Test func separateChordsByGap() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 0.5, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 2.5, note: 64, velocity: 80),
        ])
        let chords = indexed.chords()
        #expect(chords.count == 2)
    }

    @Test func chordLeadingOnset() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 2, note: 60, velocity: 100),
            MIDINote(onset: 1.05, offset: 2, note: 64, velocity: 80),
        ])
        let chords = indexed.chords()
        #expect(chords[0].leadingOnset == 1.0)
    }

    @Test func chordTrailingOffset() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 2.5, note: 60, velocity: 100),
            MIDINote(onset: 1, offset: 2.0, note: 64, velocity: 80),
        ])
        let chords = indexed.chords()
        #expect(chords[0].trailingOffset == 2.5)
    }

    @Test func chordDuration() {
        let indexed = makeIndexed([
            MIDINote(onset: 1, offset: 3, note: 60, velocity: 100),
        ])
        let chords = indexed.chords()
        #expect(chords[0].duration == 2.0)
    }

    @Test func chordPitchSpan() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 0, offset: 1, note: 67, velocity: 80),
        ])
        let chords = indexed.chords()
        #expect(chords[0].pitchSpan == 7) // C4 to G4 = 7 semitones
    }

    @Test func chordsSortedByOnset() {
        let indexed = makeIndexed([
            MIDINote(onset: 3, offset: 4, note: 60, velocity: 100),
            MIDINote(onset: 0, offset: 1, note: 64, velocity: 80),
            MIDINote(onset: 1.5, offset: 2, note: 67, velocity: 90),
        ])
        let chords = indexed.chords()
        for i in 1..<chords.count {
            #expect(chords[i - 1].leadingOnset <= chords[i].leadingOnset)
        }
    }

    @Test func firstIndexAfterBinarySearch() {
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 64, velocity: 80),
            MIDINote(onset: 4, offset: 5, note: 67, velocity: 90),
        ])
        let chords = indexed.chords()
        #expect(chords.firstIndex(after: 1) == 1)
        #expect(chords.firstIndex(after: 3) == 2)
        #expect(chords.firstIndex(after: 5) == nil)
    }

    @Test func makeSingleHandedChords() {
        // Wide chord that spans > 12 semitones should be split
        let indexed = makeIndexed([
            MIDINote(onset: 0, offset: 1, note: 36, velocity: 100),  // C2
            MIDINote(onset: 0, offset: 1, note: 48, velocity: 100),  // C3
            MIDINote(onset: 0, offset: 1, note: 72, velocity: 100),  // C5
        ])
        let singleHanded = Chord.makeSingleHandedChords(from: indexed)
        #expect(!singleHanded.isEmpty)
        // All notes should be represented across the split
        let totalNotes = singleHanded.reduce(0) { $0 + $1.count }
        #expect(totalNotes >= 3)
    }

    @Test func chordFeaturesEmptyDefault() {
        let features = Chord.Features()
        #expect(!features.contains(.glissando))
        #expect(!features.contains(.preferLeftHand))
        #expect(!features.contains(.preferRightHand))
    }

    @Test func chordSpecDefaultDuration() {
        let spec = Chord.Spec()
        #expect(spec.duration == 0.1)
    }

    @Test func chordSpecCustomDuration() {
        let spec = Chord.Spec(duration: 0.2)
        #expect(spec.duration == 0.2)
    }

}
