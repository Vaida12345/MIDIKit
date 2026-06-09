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

    /// Verifies initialization converts a constant non-120 BPM source to the 120 BPM timeline.
    @Test func initializationNormalizesConstantTempoTo120BPM() {
        let container = MIDIContainer(
            tracks: [
                MIDITrack(
                    notes: [MIDINote(onset: 1, offset: 2, note: 60, velocity: 100)],
                    sustains: [MIDISustainEvent(onset: 0.5, offset: 1.5)]
                )
            ],
            tempo: MIDITempoTrack(tempos: [MIDITempoTrack.Tempo(timestamp: 0, tempo: 60)])
        )

        let indexed = container.indexed()

        #expect(indexed.contents[0].onset == 2)
        #expect(indexed.contents[0].offset == 4)
        #expect(indexed.sustains[0].onset == 1)
        #expect(indexed.sustains[0].offset == 3)
    }

    /// Verifies initialization converts multiple source tempos to one 120 BPM timeline.
    @Test func initializationNormalizesVariableTempoTo120BPM() {
        let container = MIDIContainer(
            tracks: [
                MIDITrack(
                    notes: [MIDINote(onset: 2, offset: 6, note: 60, velocity: 100)],
                    sustains: [MIDISustainEvent(onset: 3, offset: 7)]
                )
            ],
            tempo: MIDITempoTrack(tempos: [
                MIDITempoTrack.Tempo(timestamp: 0, tempo: 120),
                MIDITempoTrack.Tempo(timestamp: 4, tempo: 60),
            ])
        )

        let indexed = container.indexed()

        #expect(indexed.contents[0].onset == 2)
        #expect(indexed.contents[0].offset == 8)
        #expect(indexed.sustains[0].onset == 3)
        #expect(indexed.sustains[0].offset == 10)
    }

    /// Verifies close same-pitch onsets retain the later note.
    @Test func closeSamePitchNotesKeepLaterNote() {
        let container = MIDIContainer(notes: [
            MIDINote(onset: 0, offset: 0.5, note: 60, velocity: 100),
            MIDINote(onset: 0.05, offset: 1, note: 60, velocity: 80),
        ])

        let indexed = container.indexed(minimumConsecutiveNotesGap: 0.1)

        #expect(indexed.count == 1)
        #expect(indexed.contents[0].onset == 0.05)
        #expect(indexed.contents[0].offset == 1)
        #expect(indexed.contents[0].velocity == 80)
    }

    /// Verifies an earlier same-pitch note is trimmed to the configured gap.
    @Test func overlappingSamePitchNotesAreTrimmedToMinimumGap() {
        let container = MIDIContainer(notes: [
            MIDINote(onset: 0, offset: 1, note: 60, velocity: 100),
            MIDINote(onset: 0.5, offset: 1.5, note: 60, velocity: 80),
        ])

        let indexed = container.indexed(minimumConsecutiveNotesGap: 0.1)

        #expect(indexed.count == 2)
        #expect(indexed.contents[0].offset == 0.4)
        #expect(indexed.contents[1].onset == 0.5)
    }

    /// Verifies pitches are clamped into the indexed piano range before grouping.
    @Test func pitchesAreClampedIntoIndexedRange() {
        let container = MIDIContainer(notes: [
            MIDINote(onset: 0, offset: 1, note: 10, velocity: 100),
            MIDINote(onset: 2, offset: 3, note: 120, velocity: 80),
        ])

        let indexed = container.indexed()

        #expect(indexed.contents.map(\.note) == [21, 108])
        #expect(indexed.notes[21]?.count == 1)
        #expect(indexed.notes[108]?.count == 1)
    }

    /// Verifies track identity wraps across the 16 valid MIDI channels.
    @Test func multiTrackChannelsWrapAt16() {
        let tracks = (0..<17).map { trackIndex in
            MIDITrack(notes: [
                MIDINote(
                    onset: Double(trackIndex),
                    offset: Double(trackIndex) + 0.5,
                    note: UInt8(21 + trackIndex),
                    velocity: 100
                )
            ])
        }

        let indexed = MIDIContainer(tracks: tracks).indexed()

        #expect(indexed.count == 17)
        #expect(indexed.contents[0].channel == 0)
        #expect(indexed.contents[15].channel == 15)
        #expect(indexed.contents[16].channel == 0)
    }

    /// Verifies overlapping and touching sustains are merged into disjoint intervals.
    @Test func multiTrackSustainsAreMerged() {
        let container = MIDIContainer(tracks: [
            MIDITrack(sustains: [MIDISustainEvent(onset: 0, offset: 2)]),
            MIDITrack(sustains: [
                MIDISustainEvent(onset: 1, offset: 3),
                MIDISustainEvent(onset: 3, offset: 4),
                MIDISustainEvent(onset: 5, offset: 6),
            ]),
        ])

        let indexed = container.indexed()

        #expect(indexed.sustains.contents == [
            MIDISustainEvent(onset: 0, offset: 4),
            MIDISustainEvent(onset: 5, offset: 6),
        ])
    }

    /// Verifies zero is rejected as a minimum consecutive-note gap.
    @Test func zeroMinimumGapFails() async {
        await #expect(processExitsWith: .failure) {
            _ = MIDIContainer().indexed(minimumConsecutiveNotesGap: 0)
        }
    }

    /// Verifies negative values are rejected as a minimum consecutive-note gap.
    @Test func negativeMinimumGapFails() async {
        await #expect(processExitsWith: .failure) {
            _ = MIDIContainer().indexed(minimumConsecutiveNotesGap: -0.1)
        }
    }

    /// Verifies infinity is rejected as a minimum consecutive-note gap.
    @Test func infiniteMinimumGapFails() async {
        await #expect(processExitsWith: .failure) {
            _ = MIDIContainer().indexed(minimumConsecutiveNotesGap: .infinity)
        }
    }

    /// Verifies NaN is rejected as a minimum consecutive-note gap.
    @Test func nanMinimumGapFails() async {
        await #expect(processExitsWith: .failure) {
            _ = MIDIContainer().indexed(minimumConsecutiveNotesGap: .nan)
        }
    }

}
