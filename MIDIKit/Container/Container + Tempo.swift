//
//  Container + Tempo.swift
//  MIDIKit
//
//  Created by Vaida on 2025-06-10.
//

import AudioToolbox
import Essentials


public extension MIDIContainer {
    
    /// Rewrites all note, sustain, channel event, meta event and raw data timestamps so playback is represented in a single tempo domain.
    ///
    /// This preserves real-time musical timing while converting beat positions to a timeline where
    /// `constantTempo` is the only tempo. After conversion, ``tempo`` is replaced with exactly one
    /// event at timestamp `0`.
    ///
    /// Fast path: if ``tempo`` is already constant and equal to `constantTempo`, this method returns
    /// without changing notes, sustains, channel events, meta events, or tempo events.
    ///
    /// - Parameter constantTempo: The target tempo in BPM. Must be greater than `0`.
    ///
    /// - Complexity: O(*T* log *T* + *n* log *T*), where *T* is the number of tempo events and *n* the number of timestamps rewritten.
    mutating func normalizeToConstantTempo(_ constantTempo: Double) {
        precondition(constantTempo > 0, "constantTempo must be greater than 0")
        
        let defaultTempo = MIDITempoTrack.Tempo.default.beatsPerMinute
        let sortedTempoEvents = self.tempo.tempos.sorted(on: \.timestamp, by: <)
        
        func areClose(_ lhs: Double, _ rhs: Double) -> Bool {
            abs(lhs - rhs) <= 1e-9
        }
        
        // If the track already has the requested constant tempo, no rescaling is needed.
        let initialTempoAtZero: Double = sortedTempoEvents
            .last(where: { $0.timestamp <= 0 })?
            .beatsPerMinute ?? defaultTempo
        let hasConstantTempo = areClose(initialTempoAtZero, constantTempo)
            && sortedTempoEvents.allSatisfy { areClose($0.beatsPerMinute, constantTempo) }
        if hasConstantTempo { return }
        
        var effectiveTempoEvents: [MIDITempoTrack.Tempo] = [
            MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: initialTempoAtZero)
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
        
        // Where each tempo segment starts on the constant-tempo time line, summed once in order.
        let segmentStarts = [MusicTimeStamp](unsafeUninitializedCapacity: effectiveTempoEvents.count) { buffer, initializedCount in
            var scaled: MusicTimeStamp = 0
            buffer[0] = 0
            var index = 1
            while index < effectiveTempoEvents.count {
                let previous = effectiveTempoEvents[index &- 1]
                scaled += (effectiveTempoEvents[index].timestamp - previous.timestamp) * constantTempo / previous.beatsPerMinute
                buffer[index] = scaled
                index &+= 1
            }
            initializedCount = effectiveTempoEvents.count
        }
        
        /// Returns `timestamp` on the constant-tempo time line.
        ///
        /// The segment is the last tempo event at or before `timestamp`, found by binary search; times before the first event use the first tempo.
        ///
        /// - Complexity: O(log *T*), where *T* is the number of tempo events.
        func scaledTime(at timestamp: MusicTimeStamp) -> MusicTimeStamp {
            // The first index whose event starts after `timestamp`.
            var low = 1
            var high = effectiveTempoEvents.count
            while low < high {
                let middle = (low &+ high) >> 1
                if effectiveTempoEvents[middle].timestamp <= timestamp {
                    low = middle &+ 1
                } else {
                    high = middle
                }
            }
            let segment = low &- 1
            let event = effectiveTempoEvents[segment]
            return segmentStarts[segment] + (timestamp - event.timestamp) * constantTempo / event.beatsPerMinute
        }
        
        self.tracks.mutatingForEach { _, track in
            track.notes.mutatingForEach { _, note in
                note.onset = scaledTime(at: note.onset)
                note.offset = scaledTime(at: note.offset)
            }
            
            track.sustains = track.sustains.transformed { MIDISustainEvent(onset: scaledTime(at: $0.onset), offset: scaledTime(at: $0.offset)) }

            for index in track.channelEvents.contents.indices {
                track.channelEvents.contents[index].onset = scaledTime(at: track.channelEvents.contents[index].onset)
            }

            for index in track.metaEvents.indices {
                track.metaEvents[index].timestamp = scaledTime(at: track.metaEvents[index].timestamp)
            }

            for index in track.rawData.indices {
                track.rawData[index].timestamp = scaledTime(at: track.rawData[index].timestamp)
            }
        }

        // The tempo track's own meta events, such as time and key signatures.
        for index in self.tempo.metaEvents.indices {
            self.tempo.metaEvents[index].timestamp = scaledTime(at: self.tempo.metaEvents[index].timestamp)
        }

        self.tempo.tempos = [MIDITempoTrack.Tempo(timestamp: 0, beatsPerMinute: constantTempo)]
    }
}
