//
//  ExternalTransformTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-21.
//

import Testing
import MIDIKit
import IndexedTrack // not `@testable`: this file sees only the public API, as a client package would.


/// `applyingGap(ideal:minimumNoteLength:)`, written as a client package would write it.
private func externalApplyingGap(_ track: IndexedTrack, ideal: Double = 1/8, minimumNoteLength: Double = 1/128) -> IndexedTrack {
    let lanes = track.lanes
    return track.modifyingNotes { notes in
        for lane in lanes {
            for (current, next) in zip(lane.noteIndices, lane.noteIndices.dropFirst()) {
                notes[current].offset = Swift.min(notes[current].offset, Swift.max(notes[next].onset - ideal, notes[current].onset + minimumNoteLength))
            }
        }
    }
}

/// Ends every note by the onset of the next chord, in the shape of `normalizing(preserve:)`.
private func externalChordClamp(_ track: IndexedTrack) -> IndexedTrack {
    let chords = track.chords
    return track.modifyingNotes { notes in
        for (chord, next) in zip(chords, chords.dropFirst()) {
            for index in chord.noteIndices {
                notes[index].offset = Swift.max(notes[index].onset, Swift.min(notes[index].offset, next.leadingOnset))
            }
        }
    }
}


/// Transforms written outside the package, with only its public API.
@Suite(.timeLimit(.minutes(1)))
struct ExternalTransformTests {
    
    @Test(arguments: 0..<10)
    func applyingGapCanBeWrittenOutside(seed: Int) {
        let indexed = track(cleanInput(seed: UInt64(seed) &+ 700, count: 300))
        #expect(externalApplyingGap(indexed).notes == indexed.applyingGap().notes)
    }
    
    @Test(arguments: 0..<5)
    func chordTransformsCanBeWrittenOutside(seed: Int) {
        let indexed = track(cleanInput(seed: UInt64(seed) &+ 800, count: 300))
        let clamped = externalChordClamp(indexed)
        let chords = indexed.chords
        for (chord, next) in zip(chords, chords.dropFirst()) {
            for index in chord.noteIndices {
                #expect(clamped.notes[index].offset <= Swift.max(next.leadingOnset, clamped.notes[index].onset))
            }
        }
        #expect(clamped.notes.map(\.onset) == indexed.notes.map(\.onset))
    }
    
}
