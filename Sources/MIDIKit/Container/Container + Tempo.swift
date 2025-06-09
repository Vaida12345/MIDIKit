//
//  Container + Tempo.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import AudioToolbox
import Essentials


public extension MIDIContainer {
    
    /// Apply the tempo.
    ///
    /// - Precondition: This function assumes the container is in constant tempo.
    ///
    /// ```swift
    /// // start by normalizing tempo
    /// let referenceNoteLength = container.tracks[0].notes.deriveReferenceNoteLength()
    ///
    /// let tempo = 120 * 1/4 / referenceNoteLength
    /// container.applyTempo(tempo: tempo)
    /// ```
    mutating func applyTempo(tempo: Double) {
        precondition(self.tempo.isEmpty || (self.tempo.count == 1 && self.tempo[0] == .init(timestamp: 0, tempo: 120)))
        
        if self.tempo.isEmpty {
            self.tempo.contents.append(MIDITempoTrack.Tempo(timestamp: 0, tempo: tempo))
        } else {
            self.tempo[0].tempo = tempo
        }
        
        let factor = tempo / 120
        
        self.tracks.mutatingForEach { index, element in
            element.notes.mutatingForEach { index, element in
                element.onset *= factor
                element.offset *= factor
            }
            
            element.sustains.mutatingForEach { index, element in
                element.onset *= factor
                element.offset *= factor
            }
            
            element.metaEvents.mutatingForEach { index, element in
                element.timestamp *= factor
            }
        }
    }
    
    mutating func adjustMIDINotesToConstantTempo(_ constantTempo: Double) {
        // Function to calculate time scaled to the constant tempo
        func scaledTime(at timestamp: MusicTimeStamp, tempoEvents: [MIDITempoTrack.Tempo], constantTempo: Double) -> MusicTimeStamp {
            var lastTempoChangeTime: MusicTimeStamp = 0
            var lastTempo: Double = tempoEvents.first?.tempo ?? constantTempo
            var scaledTime: MusicTimeStamp = 0
            
            for tempoEvent in tempoEvents {
                if timestamp < tempoEvent.timestamp {
                    break
                }
                
                let timeDifference = tempoEvent.timestamp - lastTempoChangeTime
                let scaledTimeSegment = timeDifference * constantTempo / lastTempo
                scaledTime += scaledTimeSegment
                
                lastTempoChangeTime = tempoEvent.timestamp
                lastTempo = tempoEvent.tempo
            }
            
            // Scale remaining time up to the note's timestamp
            let remainingTime = timestamp - lastTempoChangeTime
            scaledTime += remainingTime * constantTempo / lastTempo
            
            return scaledTime
        }
        
        
        self.tracks.mutatingForEach { index, track in
            track.notes.mutatingForEach { _, note in
                note.onset = scaledTime(at: note.onset, tempoEvents: self.tempo.contents, constantTempo: constantTempo)
                note.offset = scaledTime(at: note.offset, tempoEvents: self.tempo.contents, constantTempo: constantTempo)
            }
            
            track.sustains.mutatingForEach { _, sustain in
                sustain.onset = scaledTime(at: sustain.onset, tempoEvents: self.tempo.contents, constantTempo: constantTempo)
                sustain.offset = scaledTime(at: sustain.offset, tempoEvents: self.tempo.contents, constantTempo: constantTempo)
            }
        }
        
        self.tempo.contents = [MIDITempoTrack.Tempo(timestamp: 0, tempo: constantTempo)]
    }
    
    /// - Parameters:
    ///   - tempos: The timestamps are defined in *currentTempo*. Such values will be scaled in the results.
    ///   - currentTempo: The current tempo of the container. The tempo is 120 by default, or can be access via `self.tempo`
    mutating func adjustMIDINotesToVariadicTempo(_ tempos: [MIDITempoTrack.Tempo], currentTempo: Double) {
        guard !tempos.isEmpty else { return }
        
        // *= newTempo / originalTempo
        
        var tempos = tempos
        tempos[0] = MIDITempoTrack.Tempo(timestamp: 0, tempo: tempos[0].tempo)
        
        // Function to calculate time scaled to the variadic tempo
        func scaledTime(at timestamp: MusicTimeStamp, tempoEvents: [MIDITempoTrack.Tempo], constantTempo: Double) -> MusicTimeStamp {
            
            var scaled: Double = 0
            var tempoIterator = tempoEvents.sorted(on: \.timestamp, by: <).makeIterator()
            var currentTempo = tempoIterator.next()! // with the guard, this will never be `nil`.
            
            while let nextTempo = tempoIterator.next() {
                if timestamp < nextTempo.timestamp { break }
                
                let duration = nextTempo.timestamp - currentTempo.timestamp
                scaled += duration * (currentTempo.tempo / constantTempo)
                
                currentTempo = nextTempo
            }
            
            let duration = timestamp - currentTempo.timestamp
            scaled += duration * (currentTempo.tempo / constantTempo)
            
            return scaled
        }
        
        self.tracks.mutatingForEach { index, track in
            track.notes.mutatingForEach { _, note in
                note.onset = scaledTime(at: note.onset, tempoEvents: tempos, constantTempo: currentTempo)
                note.offset = scaledTime(at: note.offset, tempoEvents: tempos, constantTempo: currentTempo)
            }
            
            track.sustains.mutatingForEach { _, sustain in
                sustain.onset = scaledTime(at: sustain.onset, tempoEvents: tempos, constantTempo: currentTempo)
                sustain.offset = scaledTime(at: sustain.offset, tempoEvents: tempos, constantTempo: currentTempo)
            }
        }
        
        self.tempo.contents = tempos.map {
            MIDITempoTrack.Tempo(timestamp: scaledTime(at: $0.timestamp, tempoEvents: tempos, constantTempo: currentTempo), tempo: $0.tempo)
        }
    }
    
}
