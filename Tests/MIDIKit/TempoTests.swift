//
//  TempoTests.swift
//  MIDIKit
//
//  Created by Codex on 2026-04-02.
//

import MIDIKit
import Testing
import Foundation


@Suite("Tempo")
struct TempoTests {
    
    @Test
    func normalizeToConstantTempoFastPathWhenAlreadyConstant() {
        let original = MIDIContainer(
            tracks: [
                MIDITrack(
                    notes: [MIDINote(onset: 1, offset: 2, pitch: 60, velocity: 100)],
                    sustains: [MIDISustainEvent(onset: 0.5, offset: 1.5)]
                )
            ],
            tempo: MIDITempoTrack(tempos: [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: 100)])
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
                    notes: [MIDINote(onset: 2, offset: 6, pitch: 60, velocity: 100)],
                    sustains: [MIDISustainEvent(onset: 3, offset: 7)]
                )
            ],
            tempo: MIDITempoTrack(tempos: [
                MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: 120),
                MIDITempoTrack.Tempo(timestamp: 4, beatsPerMinute: 60),
            ])
        )
        
        container.normalizeToConstantTempo(120)
        
        let note = container.tracks[0].notes[0]
        let sustain = container.tracks[0].sustains[0]
        #expect(note.onset == 2)
        #expect(note.offset == 8)
        #expect(sustain.onset == 3)
        #expect(sustain.offset == 10)
        #expect(container.tempo.tempos == [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: 120)])
    }

    @Test
    func normalizeToConstantTempoScalesTempoTrackMetaEvents() {
        let keySignature = MIDIMetaEvent(timestamp: 2, type: 0x59, data: Data([2, 0]))
        var container = MIDIContainer(
            tracks: [MIDITrack(notes: [MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100)])],
            tempo: MIDITempoTrack(metaEvents: [keySignature], tempos: [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: 60)])
        )

        container.normalizeToConstantTempo(120)

        #expect(container.tempo.metaEvents.map(\.timestamp) == [4])
    }

    @Test
    func normalizeToConstantTempoScalesRawData() {
        var track = MIDITrack(notes: [MIDINote(onset: 0, offset: 1, pitch: 60, velocity: 100)])
        track.rawData = [MIDIRawData(timestamp: 2, data: Data([0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]))]
        var container = MIDIContainer(tracks: [track], tempo: MIDITempoTrack(tempos: [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: 60)]))

        container.normalizeToConstantTempo(120)

        #expect(container.tracks[0].rawData.map(\.timestamp) == [4])
    }

    @Test
    func normalizeToConstantTempoUsesDefaultTempoBeforeFirstEvent() {
        var container = MIDIContainer(
            tracks: [
                MIDITrack(
                    notes: [MIDINote(onset: 2, offset: 6, pitch: 60, velocity: 100)]
                )
            ],
            tempo: MIDITempoTrack(tempos: [
                MIDITempoTrack.Tempo(timestamp: 4, beatsPerMinute: 60),
            ])
        )
        
        container.normalizeToConstantTempo(60)
        
        let note = container.tracks[0].notes[0]
        #expect(note.onset == 1)
        #expect(note.offset == 4)
        #expect(container.tempo.tempos == [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: 60)])
    }

    /// The precomputed tempo map gives exactly what walking the tempo events for every timestamp gave.
    @Test(arguments: 0..<10 as Range<UInt64>)
    func normalizeToConstantTempoMatchesTheTempoWalk(seed: UInt64) {
        var generator = SplitMix64(state: seed)
        var tempos = [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: Double.random(in: 40...200, using: &generator))]
        for _ in 0..<200 {
            tempos.append(MIDITempoTrack.Tempo(timestamp: tempos.last!.timestamp + Double.random(in: 0.01...4, using: &generator), beatsPerMinute: Double.random(in: 40...200, using: &generator)))
        }
        let onsets = (0..<2000).map { _ in Double.random(in: 0...(tempos.last!.timestamp + 20), using: &generator) } + tempos.map(\.timestamp)
        var container = MIDIContainer(
            tracks: [MIDITrack(notes: onsets.map { MIDINote(onset: $0, offset: $0 + 0.5, pitch: 60, velocity: 100) })],
            tempo: MIDITempoTrack(tempos: tempos)
        )

        /// The previous algorithm: walk the tempo events from the start for every timestamp.
        func walked(_ timestamp: Double) -> Double {
            var scaled = 0.0
            var current = tempos[0]
            for next in tempos.dropFirst() {
                if timestamp < next.timestamp { break }
                scaled += (next.timestamp - current.timestamp) * 120 / current.beatsPerMinute
                current = next
            }
            return scaled + (timestamp - current.timestamp) * 120 / current.beatsPerMinute
        }

        container.normalizeToConstantTempo(120)

        #expect(container.tracks[0].notes.map(\.onset) == onsets.map(walked))
        #expect(container.tracks[0].notes.map(\.offset) == onsets.map { walked($0 + 0.5) })
    }

    /// A dense tempo map, one tempo per beat as in a performance aligned to a score, converts quickly.
    @Test(.timeLimit(.minutes(1)))
    func normalizeToConstantTempoWithADenseTempoMap() {
        let tempos = (0..<5000).map { MIDITempoTrack.Tempo(timestamp: Double($0), beatsPerMinute: 90 + Double($0 % 7) * 5) }
        let notes = (0..<20_000).map { MIDINote(onset: Double($0) / 4, offset: Double($0) / 4 + 0.2, pitch: UInt8(40 + $0 % 40), velocity: 100) }
        var container = MIDIContainer(tracks: [MIDITrack(notes: notes)], tempo: MIDITempoTrack(tempos: tempos))

        let clock = ContinuousClock()
        let start = clock.now
        container.normalizeToConstantTempo(120)

        #expect(start.duration(to: clock.now) < .seconds(1))
        #expect(container.tempo.tempos == [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: 120)])
    }

}


/// A deterministic generator, so random cases are reproducible.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
