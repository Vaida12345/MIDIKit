//
//  ChordsTests.swift
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

/// A profile that wrongly forms the chords of another track, one without notes.
private struct OtherNotesProfile: AnalysisProfile {
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.generic.formChords(in: IndexedTrack(MIDIContainer()))
    }
}

/// A profile that puts every note in a chord of its own.
private struct SingleNoteProfile: AnalysisProfile {
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        var builder = IndexedTrack.Chords.Builder(for: track)
        for index in track.notes.indices {
            builder.append(CollectionOfOne(index))
        }
        return builder.build()
    }
}

/// The chords as lists of note indices, and whether each is a glissando.
private func partition(_ chords: IndexedTrack.Chords) -> (members: [[Int]], glissando: [Bool]) {
    (chords.map { chord in chord.indices.map { chord.noteIndex(at: $0) } }, chords.map { $0.features.contains(.glissando) })
}

/// A run of `count` short notes a semitone apart, 0.1 beat apart.
private func run(count: Int, from start: Double = 0, ascending: Bool = true) -> [MIDINote] {
    (0..<count).map { index in
        let pitch = ascending ? 48 + index : 80 - index
        return note(start + Double(index) / 10, start + Double(index) / 10 + 0.05, UInt8(pitch))
    }
}


// MARK: - Tests

@Suite(.timeLimit(.minutes(1)))
struct ChordsTests {

    /// ``ChordArbiter/transkun`` was tuned on the output of Transkun 1.3.0, with both the release and the velocity cues on.
    @Test
    func transkunPresetIsPinned() {
        let transkun = ChordArbiter.transkun
        #expect([transkun.stepLimit, transkun.octaveLimit, transkun.otherLimit, transkun.previousWeight, transkun.nextWeight, transkun.isolationKnee, transkun.isolationCap, transkun.isolationFloor] == [20, 45, 40, 0.3, 0.1, 2, 5.5, 0.6])
        #expect([transkun.densityWeight, transkun.densityCenter, transkun.densityWindow, transkun.releaseWeight, transkun.releaseScale, transkun.releaseCap, transkun.velocityWeight, transkun.velocityCenter, transkun.velocityCap] == [-0.14, 4, 200, 0.15, 15, 4.5, 0.15, 60, 4])
        #expect(transkun.maximumSize == 24)

        let indexed = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: cleanInput(seed: 7, count: 200))]), profile: TranskunProfile())
        #expect(partition(indexed.chords).members == partition(ChordArbiter.transkun.formChords(in: indexed)).members)
    }

    @Test
    func glissando() {
        let indexed = track(run(count: 12) + run(count: 12, from: 5, ascending: false))
        let chords = indexed.chords
        #expect(chords.count == 24)
        #expect(chords.allSatisfy { $0.count == 1 && $0.features.contains(.glissando) })
    }

    /// A run only counts when its first note starts and ends within the same sustain state.
    @Test
    func glissandoFollowsTheSustains() {
        let sustains = [MIDISustainEvent(onset: 0.02, offset: 0.9), MIDISustainEvent(onset: 3, offset: 4)]
        let indexed = track(run(count: 12) + run(count: 11, from: 3), sustains: sustains)
        let new = partition(indexed.chords)
        #expect(new.glissando.contains(true))
        #expect(new.glissando.contains(false))
    }

    @Test
    func usesTheProfile() {
        let indexed = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: [note(0, 1, 60), note(0, 1, 64), note(0, 1, 67)])]), profile: SingleNoteProfile())
        #expect(indexed.chords.count == 3)
        #expect(GenericProfile().formChords(in: indexed).count == 1)
    }

    /// The builder checks the chords in release builds too: an empty chord stops the program instead of reaching the analyses.
    @Test
    func anEmptyChordStopsTheProgram() async {
        await #expect(processExitsWith: .failure) {
            var builder = IndexedTrack.Chords.Builder(for: IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: [note(0, 1, 60)])])))
            builder.append([0])
            builder.append([])
            _ = builder.build()
        }
    }

    /// Chords formed for other notes are never stored, as the analyses index the track's notes with them.
    @Test
    func chordsForOtherNotesStopTheProgram() async {
        await #expect(processExitsWith: .failure) {
            let indexed = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: [note(0, 1, 60), note(2, 3, 64)])]), profile: OtherNotesProfile())
            _ = indexed.chords
        }
    }

    @Test
    func isCached() {
        let indexed = track(cleanInput(seed: 3, count: 200))
        let first = indexed.chords
        let second = indexed.chords
        #expect(first.members == second.members)
        #expect(first.starts == second.starts)
        #expect(indexed.cache.chords.withLock { $0 != nil })

        let transformed = indexed.applyingGap()
        #expect(transformed.cache.chords.withLock { $0 == nil })
        #expect(transformed.chords.notes == transformed.notes)
    }

    @Test
    func chordAccessors() throws {
        let indexed = track([note(1, 2, 60), note(1.01, 3, 72), note(1.02, 1.5, 64), note(5, 6, 40)])
        let chords = indexed.chords
        try #require(chords.count == 2)

        let chord = chords[0]
        #expect(chord.count == 3)
        #expect(chord.map(\.pitch) == [60, 72, 64])
        #expect((0..<3).map { chord.noteIndex(at: $0) } == [0, 1, 2])
        #expect(chord.leadingOnset == 1)
        #expect(chord.maxOffset == 3)
        #expect(chord.duration == 2)
        #expect(chord.pitchRange == 60...72)
        #expect(chords[1].pitchRange == 40...40)
        #expect(chords[1].leadingOnset == 5)
    }

    @Test
    func edgeCases() {
        #expect(track([]).chords.isEmpty)
        let single = track([note(0, 1, 60)]).chords
        #expect(single.count == 1)
        #expect(single[0].count == 1)
    }

}
