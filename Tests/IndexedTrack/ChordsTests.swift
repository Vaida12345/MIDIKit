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

/// The chords the old arbiter forms for the same notes, in the same form as `partition(_:)`.
private func oldPartition(of track: IndexedTrack, optimizeFor algorithm: TranscriptionAlgorithm?) -> (members: [[Int]], glissando: [Bool]) {
    let old = IndexedContainer(container: track.makeContainer())
    defer { withExtendedLifetime(old) {} }

    let ordered = ChordFigures.orderedNotes(of: old)
    #expect(ordered.map(\.pointee) == track.notes, "The old container must hold the same notes in the same order.")

    var position: [ReferenceNote: Int] = [:]
    for (index, note) in ordered.enumerated() { position[note] = index }
    let chords = Chord.makeChords(from: old, optimizeFor: algorithm)
        .map { chord in (members: chord.map { position[$0]! }.sorted(), glissando: chord.features.contains(.glissando)) }
        .sorted { $0.members[0] < $1.members[0] }
    return (chords.map(\.members), chords.map(\.glissando))
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

    @Test(arguments: 0..<30)
    func matchesTheOldGenericArbiter(seed: Int) {
        let indexed = track(ChordFigures.notes(seed: UInt64(seed)))
        let new = partition(indexed.chords)
        let old = oldPartition(of: indexed, optimizeFor: nil)
        #expect(new.members == old.members)
        #expect(new.glissando == old.glissando)
    }

    /// The release and velocity cues are off in `.generic`; the transcriber profiles turn them on.
    @Test(arguments: 0..<30)
    func matchesTheOldTunedArbiters(seed: Int) {
        let notes = ChordFigures.notes(seed: UInt64(seed) &+ 1000)
        let profiles: [(any AnalysisProfile, TranscriptionAlgorithm)] = [(TranskunProfile(), .transkun), (PianoTranscriptionProfile(), .pianoTranscription)]
        for (profile, algorithm) in profiles {
            let indexed = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: notes)]), profile: profile)
            let new = partition(indexed.chords)
            let old = oldPartition(of: indexed, optimizeFor: algorithm)
            #expect(new.members == old.members, "\(algorithm)")
            #expect(new.glissando == old.glissando, "\(algorithm)")
        }
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
        let old = oldPartition(of: indexed, optimizeFor: nil)
        #expect(new.members == old.members)
        #expect(new.glissando == old.glissando)
        #expect(new.glissando.contains(true))
        #expect(new.glissando.contains(false))
    }

    @Test
    func usesTheProfile() {
        let indexed = IndexedTrack(MIDIContainer(tracks: [MIDITrack(notes: [note(0, 1, 60), note(0, 1, 64), note(0, 1, 67)])]), profile: SingleNoteProfile())
        #expect(indexed.chords.count == 3)
        #expect(GenericProfile().formChords(in: indexed).count == 1)
    }

    @Test
    func isCached() {
        let indexed = track(ChordFigures.notes(seed: 3))
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
