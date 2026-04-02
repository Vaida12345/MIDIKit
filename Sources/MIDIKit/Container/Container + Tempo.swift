//
//  Container + Tempo.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import AudioToolbox
import Essentials


public extension MIDIContainer {
    
    /// Rewrites all note and sustain timestamps so playback is represented in a single tempo domain.
    ///
    /// This preserves real-time musical timing while converting beat positions to a timeline where
    /// `constantTempo` is the only tempo. After conversion, ``tempo`` is replaced with exactly one
    /// event at timestamp `0`.
    ///
    /// Fast path: if ``tempo`` is already constant and equal to `constantTempo`, this method returns
    /// without changing notes, sustains, or tempo events.
    ///
    /// - Parameter constantTempo: The target tempo in BPM. Must be greater than `0`.
    mutating func normalizeToConstantTempo(_ constantTempo: Double) {
        precondition(constantTempo > 0, "constantTempo must be greater than 0")
        
        let defaultTempo = MIDITempoTrack.Tempo.default.tempo
        let sortedTempoEvents = self.tempo.contents.sorted(on: \.timestamp, by: <)
        
        func areClose(_ lhs: Double, _ rhs: Double) -> Bool {
            abs(lhs - rhs) <= 1e-9
        }
        
        // If the track already has the requested constant tempo, no rescaling is needed.
        let initialTempoAtZero: Double = sortedTempoEvents
            .last(where: { $0.timestamp <= 0 })?
            .tempo ?? defaultTempo
        let hasConstantTempo = areClose(initialTempoAtZero, constantTempo)
            && sortedTempoEvents.allSatisfy { areClose($0.tempo, constantTempo) }
        if hasConstantTempo { return }
        
        var effectiveTempoEvents: [MIDITempoTrack.Tempo] = [
            MIDITempoTrack.Tempo(timestamp: 0, tempo: initialTempoAtZero)
        ]
        for event in sortedTempoEvents where event.timestamp >= 0 {
            if event.timestamp == 0 {
                effectiveTempoEvents[0] = event
            } else if effectiveTempoEvents.last?.timestamp == event.timestamp {
                effectiveTempoEvents[effectiveTempoEvents.count - 1] = event
            } else {
                effectiveTempoEvents.append(event)
            }
        }
        
        // Function to calculate time scaled to the constant tempo
        func scaledTime(
            at timestamp: MusicTimeStamp,
            tempoEvents: [MIDITempoTrack.Tempo],
            constantTempo: Double
        ) -> MusicTimeStamp {
            var scaled: MusicTimeStamp = 0
            var currentTempoEvent = tempoEvents[0]
            
            for nextTempoEvent in tempoEvents.dropFirst() {
                if timestamp < nextTempoEvent.timestamp {
                    break
                }
                
                let duration = nextTempoEvent.timestamp - currentTempoEvent.timestamp
                scaled += duration * constantTempo / currentTempoEvent.tempo
                currentTempoEvent = nextTempoEvent
            }
            
            let remainingDuration = timestamp - currentTempoEvent.timestamp
            scaled += remainingDuration * constantTempo / currentTempoEvent.tempo
            return scaled
        }
        
        self.tracks.mutatingForEach { _, track in
            track.notes.mutatingForEach { _, note in
                note.onset = scaledTime(at: note.onset, tempoEvents: effectiveTempoEvents, constantTempo: constantTempo)
                note.offset = scaledTime(at: note.offset, tempoEvents: effectiveTempoEvents, constantTempo: constantTempo)
            }
            
            track.sustains.mutatingForEach { _, sustain in
                sustain.onset = scaledTime(at: sustain.onset, tempoEvents: effectiveTempoEvents, constantTempo: constantTempo)
                sustain.offset = scaledTime(at: sustain.offset, tempoEvents: effectiveTempoEvents, constantTempo: constantTempo)
            }
        }
        
        self.tempo.contents = [MIDITempoTrack.Tempo(timestamp: 0, tempo: constantTempo)]
    }
    
    /// Deprecated compatibility wrapper for ``normalizeToConstantTempo(_:)``.
    @available(*, deprecated, renamed: "normalizeToConstantTempo(_:)")
    mutating func adjustMIDINotesToConstantTempo(_ constantTempo: Double) {
        self.normalizeToConstantTempo(constantTempo)
    }
}
