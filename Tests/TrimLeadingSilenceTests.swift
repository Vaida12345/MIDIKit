//
//  TrimLeadingSilenceTests.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Testing
import Foundation
import MIDIKit


@Suite(.timeLimit(.minutes(1)))
struct TrimLeadingSilenceTests {

    @Test
    func notesAcrossTracks() {
        let container = MIDIContainer(tracks: [
            MIDITrack(notes: [MIDINote(onset: 3, offset: 4, pitch: 60, velocity: 80), MIDINote(onset: 5, offset: 5.5, pitch: 62, velocity: 80)]),
            MIDITrack(notes: [MIDINote(onset: 2, offset: 2.5, pitch: 48, velocity: 70)]),
        ])
        let result = container.trimmingLeadingSilence()

        #expect(result.tracks[0].notes.contents == [MIDINote(onset: 1, offset: 2, pitch: 60, velocity: 80), MIDINote(onset: 3, offset: 3.5, pitch: 62, velocity: 80)])
        #expect(result.tracks[1].notes.contents == [MIDINote(onset: 0, offset: 0.5, pitch: 48, velocity: 70)])
    }

    @Test
    func sustains() {
        let container = MIDIContainer(tracks: [MIDITrack(
            notes: [MIDINote(onset: 2, offset: 3, pitch: 60, velocity: 80)],
            sustains: [MIDISustainEvent(onset: 0, offset: 1), MIDISustainEvent(onset: 1.5, offset: 2), MIDISustainEvent(onset: 1.8, offset: 2.5), MIDISustainEvent(onset: 3, offset: 4)]
        )])
        let result = container.trimmingLeadingSilence()

        // Ending before or at the first note: removed. Down at the first note: starts at 0. Later: shifted.
        #expect(result.tracks[0].sustains.contents == [MIDISustainEvent(onset: 0, offset: 0.5), MIDISustainEvent(onset: 1, offset: 2)])
    }

    @Test
    func controlAndMetaEvents() {
        let name = MIDIMetaEvent(timestamp: 0, type: .trackName, data: Data("Piano".utf8))
        let container = MIDIContainer(tracks: [MIDITrack(
            notes: [MIDINote(onset: 2, offset: 3, pitch: 60, velocity: 80)],
            metaEvents: [name, MIDIMetaEvent(timestamp: 2.5, type: 1, data: Data([1]))],
            channelEvents: MIDIChannelEvents([MIDIChannelEvent(onset: 0.5, message: .controlChange(controller: 7, value: 90)), MIDIChannelEvent(onset: 1, message: .controlChange(controller: 7, value: 100)), MIDIChannelEvent(onset: 2.25, message: .controlChange(controller: 7, value: 110))])
        )])
        let result = container.trimmingLeadingSilence()

        #expect(result.tracks[0].metaEvents == [MIDIMetaEvent(timestamp: 0, type: .trackName, data: Data("Piano".utf8)), MIDIMetaEvent(timestamp: 0.5, type: 1, data: Data([1]))])
        #expect(result.tracks[0].channelEvents.contents == [MIDIChannelEvent(onset: 0, message: .controlChange(controller: 7, value: 90)), MIDIChannelEvent(onset: 0, message: .controlChange(controller: 7, value: 100)), MIDIChannelEvent(onset: 0.25, message: .controlChange(controller: 7, value: 110))])
    }

    @Test
    func tempos() {
        let notes = MIDITrack(notes: [MIDINote(onset: 4, offset: 5, pitch: 60, velocity: 80)])
        let container = MIDIContainer(
            tracks: [notes],
            tempo: MIDITempoTrack(
                events: [.defaultTimeSignature],
                tempos: [MIDITempoTrack.Tempo(timestamp: 0, tempo: 100), MIDITempoTrack.Tempo(timestamp: 2, tempo: 90), MIDITempoTrack.Tempo(timestamp: 6, tempo: 140)]
            )
        )
        let result = container.trimmingLeadingSilence()

        #expect(result.tempo.contents == [MIDITempoTrack.Tempo(timestamp: 0, tempo: 90), MIDITempoTrack.Tempo(timestamp: 2, tempo: 140)])
        #expect(result.tempo.events == [.defaultTimeSignature])
    }

    @Test
    func tempoAtTheCut() {
        let notes = MIDITrack(notes: [MIDINote(onset: 2, offset: 3, pitch: 60, velocity: 80)])
        let container = MIDIContainer(tracks: [notes], tempo: MIDITempoTrack([MIDITempoTrack.Tempo(timestamp: 0, tempo: 100), MIDITempoTrack.Tempo(timestamp: 2, tempo: 90)]))
        #expect(container.trimmingLeadingSilence().tempo.contents == [MIDITempoTrack.Tempo(timestamp: 0, tempo: 90)])
    }

    /// A file whose only tempo comes after the cut gets no tempo added at 0: the default applied before the cut, and still applies.
    @Test
    func noTempoAddedAtZero() {
        let notes = MIDITrack(notes: [MIDINote(onset: 2, offset: 3, pitch: 60, velocity: 80)])
        let container = MIDIContainer(tracks: [notes], tempo: MIDITempoTrack([MIDITempoTrack.Tempo(timestamp: 3, tempo: 90)]))
        #expect(container.trimmingLeadingSilence().tempo.contents == [MIDITempoTrack.Tempo(timestamp: 1, tempo: 90)])
    }

    @Test
    func nothingToTrim() {
        let empty = MIDIContainer(tracks: [MIDITrack(sustains: [MIDISustainEvent(onset: 1, offset: 2)])])
        #expect(empty.trimmingLeadingSilence() == empty)

        let atZero = MIDIContainer(tracks: [MIDITrack(notes: [MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 80)], sustains: [MIDISustainEvent(onset: 0.5, offset: 2)])], tempo: MIDITempoTrack([MIDITempoTrack.Tempo(timestamp: 0, tempo: 100)]))
        #expect(atZero.trimmingLeadingSilence() == atZero)
    }

    @Test
    func negativeOnsetsMoveLater() {
        let container = MIDIContainer(tracks: [MIDITrack(notes: [MIDINote(onset: -1, offset: 0.5, pitch: 60, velocity: 80)], sustains: [MIDISustainEvent(onset: 0, offset: 1)])])
        let result = container.trimmingLeadingSilence()
        #expect(result.tracks[0].notes.contents == [MIDINote(onset: 0, offset: 1.5, pitch: 60, velocity: 80)])
        #expect(result.tracks[0].sustains.contents == [MIDISustainEvent(onset: 1, offset: 2)])
    }

    @Test
    func mutatingAndReturningAgree() {
        let container = MIDIContainer(tracks: [MIDITrack(
            notes: [MIDINote(onset: 1.5, offset: 3, pitch: 60, velocity: 80)],
            sustains: [MIDISustainEvent(onset: 1, offset: 2)]
        )], tempo: MIDITempoTrack([MIDITempoTrack.Tempo(timestamp: 1, tempo: 80)]))
        var mutated = container
        mutated.trimLeadingSilence()
        #expect(mutated == container.trimmingLeadingSilence())
    }

    @Test
    func roundTrip() throws {
        let container = MIDIContainer(
            tracks: [MIDITrack(notes: [MIDINote(onset: 2, offset: 3, pitch: 60, velocity: 80), MIDINote(onset: 4, offset: 4.5, pitch: 64, velocity: 80)])],
            tempo: MIDITempoTrack(events: [.defaultTimeSignature], tempos: [MIDITempoTrack.Tempo(timestamp: 0, tempo: 100), MIDITempoTrack.Tempo(timestamp: 1, tempo: 90)])
        )
        let trimmed = container.trimmingLeadingSilence()
        let loaded = try MIDIContainer(data: trimmed.data())

        #expect(loaded.tracks.flatMap(\.notes.contents) == trimmed.tracks.flatMap(\.notes.contents))
        // MIDI stores tempos as whole microseconds per beat, so 90 comes back as about 90.00009.
        let first = try #require(loaded.tempo.contents.first)
        #expect(first.timestamp == 0)
        #expect(abs(first.tempo - 90) < 0.001)
    }

}
