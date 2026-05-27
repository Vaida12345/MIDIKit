//
//  TrackAndMeasureTests.swift
//  MIDIKit
//

@testable
import MIDIKit
import Testing


@Suite("MIDITrack")
struct MIDITrackTests {

    @Test func initEmpty() {
        let track = MIDITrack()
        #expect(track.notes.isEmpty)
        #expect(track.sustains.isEmpty)
        #expect(track.metaEvents.isEmpty)
        #expect(track.rawData.isEmpty)
    }

    @Test func initWithNotesArray() {
        let notes = [
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 64, velocity: 80),
        ]
        let track = MIDITrack(notes: notes)
        #expect(track.notes.count == 2)
    }

    @Test func initWithNotesAndSustains() {
        let notes = [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)]
        let sustains = MIDISustainEvents([MIDISustainEvent(onset: 0, offset: 1)])
        let track = MIDITrack(notes: notes, sustains: sustains)
        #expect(track.notes.count == 1)
        #expect(track.sustains.count == 1)
    }

    @Test func initWithNotesCollection() {
        let notes = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let track = MIDITrack(notes: notes, sustains: MIDISustainEvents())
        #expect(track.notes.count == 1)
    }

    @Test func initWithAllVariants() {
        let track = MIDITrack(
            notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)],
            sustains: [MIDISustainEvent(onset: 0, offset: 1)],
            metaEvents: [MIDIMetaEvent.defaultTimeSignature]
        )
        #expect(track.notes.count == 1)
        #expect(track.sustains.count == 1)
        #expect(track.metaEvents.count == 1)
    }

    @Test func range() {
        let track = MIDITrack(notes: [
            MIDINote(onset: 1.0, offset: 3.0, note: 60, velocity: 100),
            MIDINote(onset: 2.0, offset: 5.0, note: 64, velocity: 80),
        ])
        #expect(track.range.lowerBound == 1.0)
        #expect(track.range.upperBound == 5.0)
    }

    @Test func rangeEmptyTrack() {
        let track = MIDITrack()
        #expect(track.range.lowerBound == 0.0)
        #expect(track.range.upperBound == 0.0)
    }

    @Test func appendNotes() {
        var track1 = MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let track2 = MIDITrack(notes: [MIDINote(onset: 2, offset: 3, note: 64, velocity: 80)])
        track1.appendNotes(from: track2)
        #expect(track1.notes.count == 2)
    }

    @Test func equatable() {
        let a = MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let b = MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        #expect(a == b)
    }

    @Test func notEqualDifferentNotes() {
        let a = MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let b = MIDITrack(notes: [MIDINote(onset: 0, offset: 1, note: 64, velocity: 100)])
        #expect(a != b)
    }

}


@Suite("MIDITrack.Quantize")
struct MIDITrackQuantizeTests {

    @Test func quantizeQuarterNotes() {
        var track = MIDITrack(notes: [
            MIDINote(onset: 0.05, offset: 0.95, note: 60, velocity: 100),
            MIDINote(onset: 1.02, offset: 1.98, note: 64, velocity: 80),
        ])
        track.quantize(by: 1.0)
        // Should quantize to nearest beat
        #expect(track.notes[0].onset == 0.0)
        #expect(track.notes[1].onset == 1.0)
    }

    @Test func quantizePreservesMinimumDuration() {
        var track = MIDITrack(notes: [
            MIDINote(onset: 0.02, offset: 0.1, note: 60, velocity: 100),
        ])
        track.quantize(by: 1.0)
        // Duration should be at least 0.25 (1/4)
        #expect(track.notes[0].duration >= 0.25)
    }

    @Test func quantizeSustains() {
        var track = MIDITrack(
            sustains: [
                MIDISustainEvent(onset: 0.08, offset: 2.92),
            ]
        )
        track.quantize(by: 1.0)
        #expect(track.sustains[0].onset == 0.0)
        #expect(track.sustains[0].offset == 3.0)
    }

}


@Suite("MIDITrack.Measures")
struct MIDITrackMeasuresTests {

    @Test func emptyTrackReturnsNoMeasures() {
        let track = MIDITrack()
        #expect(track.measures(timeSignature: (4, 4)).isEmpty)
    }

    @Test func fourFourMeasures() {
        let track = MIDITrack(notes: [
            MIDINote(onset: 0.0, offset: 1.0, note: 60, velocity: 100),
            MIDINote(onset: 1.0, offset: 2.0, note: 64, velocity: 80),
            MIDINote(onset: 4.0, offset: 5.0, note: 67, velocity: 90), // measure 2
        ])
        let measures = track.measures(timeSignature: (4, 4))
        #expect(measures.count >= 2)
        #expect(measures[0].notes.count == 2)
        #expect(measures[1].notes.count == 1)
    }

}


@Suite("MIDIMeasure")
struct MIDIMeasureTests {

    @Test func initEmpty() {
        let measure = MIDIMeasure()
        #expect(measure.notes.isEmpty)
        #expect(measure.sustains.isEmpty)
    }

    @Test func initWithNotes() {
        let notes = MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)])
        let measure = MIDIMeasure(notes: notes)
        #expect(measure.notes.count == 1)
    }

    @Test func jointedCombinesMeasures() {
        let m1 = MIDIMeasure(
            notes: MIDINotes([MIDINote(onset: 0, offset: 1, note: 60, velocity: 100)]),
            sustains: MIDISustainEvents([MIDISustainEvent(onset: 0, offset: 1)])
        )
        let m2 = MIDIMeasure(
            notes: MIDINotes([MIDINote(onset: 4, offset: 5, note: 64, velocity: 80)]),
            sustains: MIDISustainEvents([MIDISustainEvent(onset: 3, offset: 5)])
        )
        let combined = [m1, m2].jointed()
        #expect(combined.notes.count == 2)
        #expect(combined.sustains.count == 2)
    }

    @Test func jointedEmptyArray() {
        let combined: MIDIMeasure = [].jointed()
        #expect(combined.notes.isEmpty)
        #expect(combined.sustains.isEmpty)
    }

}
