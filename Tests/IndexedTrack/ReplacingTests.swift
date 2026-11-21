//
//  ReplacingTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-21.
//

import Testing
import Foundation
import MIDIKit
@testable
import IndexedTrack


/// A profile to recognize after a round trip.
private struct ReplacingProfile: AnalysisProfile {
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.generic.formChords(in: track)
    }
}

/// A track with every kind of event besides notes and sustains: a program change, a SysEx message, a marker and a time signature.
private func richTrack(profile: some AnalysisProfile = .generic) -> IndexedTrack {
    var source = MIDITrack(
        notes: [note(0, 1, 60), note(1, 2, 64)],
        sustains: [MIDISustainEvent(onset: 0, offset: 1.5)],
        metaEvents: [MIDIMetaEvent(timestamp: 0.5, type: 0x06, data: Data("marker".utf8))],
        channelEvents: MIDIChannelEvents([MIDIChannelEvent(onset: 0, message: .programChange(program: 3))])
    )
    source.rawData = [MIDIKit.MIDIRawData(timestamp: 0, data: Data([0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]))]
    var tempo = MIDITempoTrack(tempos: [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: 120)])
    tempo.timeSignature = MIDITimeSignature(3, 4)
    return IndexedTrack(MIDIContainer(tracks: [source], tempo: tempo), profile: profile)
}


@Suite(.timeLimit(.minutes(1)))
struct ReplacingTests {

    /// The notes go in exactly as given, and indexing the result cleans them up as the initializer does.
    @Test
    func notesGoInAsGiven() {
        let notes = [note(3, 4, 67), note(2, 3, 120), note(0, 1, 60)]
        let container = richTrack().replacing(notes: notes)
        #expect(container.tracks[0].notes.contents == notes)
        #expect(container.indexed().notes == [note(0, 1, 60), note(3, 4, 67)])
    }

    /// Every event besides the notes is the one ``IndexedTrack/makeContainer()`` returns.
    @Test
    func everythingElseIsKept() {
        let track = richTrack()
        let made = track.makeContainer()
        let replaced = track.replacing(notes: [note(5, 6, 72)])

        #expect(replaced.tracks.count == 1)
        #expect(replaced.tracks[0].sustains == made.tracks[0].sustains)
        #expect(replaced.tracks[0].channelEvents == made.tracks[0].channelEvents)
        #expect(replaced.tracks[0].metaEvents == made.tracks[0].metaEvents)
        #expect(replaced.tracks[0].rawData == made.tracks[0].rawData)
        #expect(replaced.tempo == made.tempo)
        #expect(replaced.tempo.timeSignature == MIDITimeSignature(3, 4))
    }

    @Test
    func sustainsAreReplacedAndNotesKept() {
        let track = richTrack()
        let sustains = MIDISustainEvents([MIDISustainEvent(onset: 2, offset: 3)])
        let replaced = track.replacing(sustains: sustains)
        #expect(replaced.tracks[0].sustains == sustains)
        #expect(replaced.tracks[0].notes == track.makeContainer().tracks[0].notes)
    }

    @Test
    func noArgumentsIsTheContainer() {
        let track = richTrack()
        #expect(track.replacing() == track.makeContainer())
    }

    /// Indexing the result with the track's profile keeps the profile.
    @Test
    func roundTripKeepsTheProfile() {
        let track = richTrack(profile: ReplacingProfile())
        let edited = track.replacing(notes: [note(0, 2, 60)]).indexed(profile: track.profile)
        #expect(edited.profile is ReplacingProfile)
        #expect(edited.notes == [note(0, 2, 60)])
        #expect(edited.channelEvents == track.channelEvents)
    }

}
