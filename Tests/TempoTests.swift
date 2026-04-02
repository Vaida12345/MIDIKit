//
//  TempoTests.swift
//  MIDIKit
//
//  Created by Codex on 2026-04-02.
//

import MIDIKit
import Testing


@Suite("Tempo")
struct TempoTests {
    
    @Test
    func normalizeToConstantTempoFastPathWhenAlreadyConstant() {
        let original = MIDIContainer(
            tracks: [
                MIDITrack(
                    notes: [MIDINote(onset: 1, offset: 2, note: 60, velocity: 100)],
                    sustains: [MIDISustainEvent(onset: 0.5, offset: 1.5)]
                )
            ],
            tempo: MIDITempoTrack(tempos: [MIDITempoTrack.Tempo(timestamp: 0, tempo: 100)])
        )
        var transformed = original
        
        transformed.normalizeToConstantTempo(100)
        
        #expect(transformed == original)
    }
    
    @Test
    func normalizeToConstantTempoScalesNoteAndSustainTimestamps() {
        var container = MIDIContainer(
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
        
        container.normalizeToConstantTempo(120)
        
        let note = container.tracks[0].notes[0]
        let sustain = container.tracks[0].sustains[0]
        #expect(note.onset == 2)
        #expect(note.offset == 8)
        #expect(sustain.onset == 3)
        #expect(sustain.offset == 10)
        #expect(container.tempo.contents == [MIDITempoTrack.Tempo(timestamp: 0, tempo: 120)])
    }
    
    @Test
    func normalizeToConstantTempoUsesDefaultTempoBeforeFirstEvent() {
        var container = MIDIContainer(
            tracks: [
                MIDITrack(
                    notes: [MIDINote(onset: 2, offset: 6, note: 60, velocity: 100)]
                )
            ],
            tempo: MIDITempoTrack(tempos: [
                MIDITempoTrack.Tempo(timestamp: 4, tempo: 60),
            ])
        )
        
        container.normalizeToConstantTempo(60)
        
        let note = container.tracks[0].notes[0]
        #expect(note.onset == 1)
        #expect(note.offset == 4)
        #expect(container.tempo.contents == [MIDITempoTrack.Tempo(timestamp: 0, tempo: 60)])
    }
}
