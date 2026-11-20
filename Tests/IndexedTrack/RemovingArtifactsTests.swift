//
//  RemovingArtifactsTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import MIDIKit
@testable
import IndexedTrack


// MARK: - Support

/// Runs the old `IndexedContainer.removingArtifacts` on the notes and sustains of `track`, and returns its notes sorted by (onset, pitch).
private func oldRemovingArtifacts(_ track: IndexedTrack, threshold: UInt8) -> [MIDINote] {
    let old = IndexedContainer(container: track.makeContainer())
    defer { withExtendedLifetime(old) {} }
    #expect(ChordFigures.orderedNotes(of: old).map(\.pointee) == track.notes, "The old container must hold the same notes in the same order.")

    let result = old.removingArtifacts(threshold: threshold)
    defer { withExtendedLifetime(result) {} }
    return ChordFigures.orderedNotes(of: result).map(\.pointee).sorted(by: isOrdered)
}

/// A profile that keeps every note.
private struct KeepsEverything: AnalysisProfile {
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.generic.formChords(in: track)
    }

    func removingArtifacts(from track: IndexedTrack, threshold: UInt8, proximityThreshold: Double) -> IndexedTrack {
        track
    }
}

/// A profile that implements only the required hooks.
private struct ChordsOnly: AnalysisProfile {
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.generic.formChords(in: track)
    }
}


// MARK: - Tests

@Suite(.timeLimit(.minutes(1)))
struct RemovingArtifactsTests {

    @Test(arguments: 0..<30)
    func matchesTheOldVersion(seed: Int) {
        let indexed = track(cleanInput(seed: UInt64(seed) &+ 1_300, count: 300))
        for threshold in [30, 40, 64] as [UInt8] {
            let new = indexed.removingArtifacts(threshold: threshold).notes
            let old = oldRemovingArtifacts(indexed, threshold: threshold)
            #expect(new == old, "threshold \(threshold)")
        }
    }

    /// Some seeds must remove notes, so the comparison above covers removal.
    @Test
    func theComparisonRemovesNotes() {
        let removed = (0..<30).map { seed in
            let indexed = track(cleanInput(seed: UInt64(seed) &+ 1_300, count: 300))
            return indexed.notes.count - indexed.removingArtifacts(threshold: 40).notes.count
        }
        #expect(removed.reduce(0, +) > 30)
    }

    /// The first note on a key absorbs a run, even when it is quiet itself.
    @Test
    func allQuiet() {
        let indexed = track([note(0, 1, 50, velocity: 20), note(1, 1.1, 50, velocity: 20), note(1.1, 1.3, 50, velocity: 20)])
        #expect(indexed.removingArtifacts(threshold: 30).notes == [note(0, 1.3, 50, velocity: 20)])
    }

    @Test
    func allQuietExceptTheFirst() {
        let indexed = track([note(0, 1, 50, velocity: 50), note(1, 1.1, 50, velocity: 20), note(1.1, 1.3, 50, velocity: 20)])
        #expect(indexed.removingArtifacts(threshold: 30).notes == [note(0, 1.3, 50, velocity: 50)])
    }

    @Test
    func allQuietExceptTheSecond() {
        let indexed = track([note(0, 1, 50, velocity: 20), note(1.01, 1.1, 50, velocity: 50), note(1.1, 1.3, 50, velocity: 20), note(1.3, 1.5, 50, velocity: 20)])
        #expect(indexed.removingArtifacts(threshold: 30).notes == [note(0, 1, 50, velocity: 20), note(1.01, 1.5, 50, velocity: 50)])
    }

    @Test
    func aRunFarFromTheNoteBeforeIsKept() {
        let indexed = track([note(0, 1, 50), note(2, 2.1, 50, velocity: 20)])
        #expect(indexed.removingArtifacts(threshold: 30).notes == indexed.notes)
    }

    /// A quiet note far from the run after it ends that run without starting a new one, as in the old version.
    @Test
    func aGapInsideARunEndsIt() {
        let indexed = track([note(0, 1, 50), note(1.1, 1.2, 50, velocity: 20), note(2, 2.1, 50, velocity: 20)])
        #expect(indexed.removingArtifacts(threshold: 30).notes == indexed.notes)
    }

    @Test
    func aRunAtTheEndOfAKey() {
        let indexed = track([note(0, 1, 50), note(1.1, 1.2, 50, velocity: 20), note(1.3, 1.4, 50, velocity: 20), note(0, 1, 60, velocity: 20)])
        #expect(indexed.removingArtifacts(threshold: 30).notes == [note(0, 1.4, 50), note(0, 1, 60, velocity: 20)])
    }

    @Test
    func nothingQuiet() {
        let indexed = track([note(0, 1, 50), note(1.1, 1.2, 50), note(1.3, 1.4, 50)])
        #expect(indexed.removingArtifacts(threshold: 30).notes == indexed.notes)
    }

    @Test
    func proximityThreshold() {
        let indexed = track([note(0, 1, 50), note(1.2, 1.3, 50, velocity: 20)])
        #expect(indexed.removingArtifacts(threshold: 30, proximityThreshold: 0.1).notes == indexed.notes)
        #expect(indexed.removingArtifacts(threshold: 30, proximityThreshold: 0.3).notes == [note(0, 1.3, 50)])
    }

    @Test(arguments: 0..<5)
    func keepsEverythingButNotes(seed: Int) {
        let source = MIDITrack(
            notes: cleanInput(seed: UInt64(seed) &+ 1_700, count: 150),
            sustains: [MIDISustainEvent(onset: 1, offset: 3), MIDISustainEvent(onset: 4, offset: 6)],
            metaEvents: [MIDIMetaEvent(timestamp: 1, type: 1, data: Data([1]))],
            channelEvents: MIDIChannelEvents([MIDIChannelEvent(onset: 0.5, message: .controlChange(controller: 0, value: 64))])
        )
        let indexed = IndexedTrack(MIDIContainer(tracks: [source]))
        let result = indexed.removingArtifacts(threshold: 64)

        #expect(result.notes.count < indexed.notes.count)
        #expect(result.sustains == indexed.sustains)
        #expect(result.channelEvents == indexed.channelEvents)
        #expect(result.metaEvents == indexed.metaEvents)
        #expect(result.profile is GenericProfile)
    }

    @Test
    func theProfileDecides() {
        let notes = [note(0, 1, 50), note(1.1, 1.2, 50, velocity: 20)]
        let source = MIDIContainer(tracks: [MIDITrack(notes: notes)])

        let keeping = IndexedTrack(source, profile: KeepsEverything())
        #expect(keeping.removingArtifacts(threshold: 30).notes == keeping.notes)

        // Without its own implementation, a profile gets the generic one.
        let chordsOnly = IndexedTrack(source, profile: ChordsOnly())
        let result = chordsOnly.removingArtifacts(threshold: 30)
        #expect(result.notes == [note(0, 1.2, 50)])
        #expect(result.profile is ChordsOnly)
    }

    @Test
    func edgeCases() {
        #expect(track([]).removingArtifacts(threshold: 127).notes.isEmpty)

        let single = track([note(0, 1, 50, velocity: 1)])
        #expect(single.removingArtifacts(threshold: 127).notes == single.notes)
    }

}
