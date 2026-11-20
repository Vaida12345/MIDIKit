//
//  Indexed+ApplyingVelocities.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


extension IndexedTrack {
    
    /// Returns this track with the velocities of `performance`.
    ///
    /// The typical pair is a sheet, whose velocities say nothing, and a performance of it, such as a transcription of a recording, whose velocities are right but whose timing is the player's. Each note of this track takes the velocity of its partner in `performance`:
    ///
    /// 1. The onsets of this track are mapped into the beats of `performance` through `warp`, or through ``timeWarp(to:parameters:)`` when it is `nil`.
    /// 2. On each key, the notes are paired one to one with the notes of `performance` whose onsets are within 0.15 beats, the closest first. A note never shares its partner, so repeated notes and trills each get their own velocity.
    /// 3. A note with a partner takes its velocity as it is.
    /// 4. A note without one, which `performance` misses, gets the mean velocity of the notes of `performance` around it, weighted by how far each is in time (a spread of half a beat) and in pitch (a spread of three semitones), so a missing note of the melody takes after the melody, not after the bass. As a transcriber misses mostly quiet notes, 15 is subtracted. With no note in reach, the spreads are widened four times, and then the median velocity of `performance` is used.
    ///
    /// Everything but the velocities is kept: times, keys, sustains, channel events, meta events, raw data, and the ``profile``. If either track has no notes, the result is this track.
    ///
    /// On the ASAP dataset, against the exact velocities of the MAESTRO performances, a transferred velocity is off by 2.05 on average from transkun transcriptions and by 4.08 from PianoTranscription ones, against 1.80 and 3.80 had each note's true partner been known.
    ///
    /// - Parameters:
    ///   - performance: The track to take the velocities from, which has the same piece.
    ///   - warp: The warp from the beats of this track to the beats of `performance`. Pass one to reuse it, or to use other parameters than the default ones of ``timeWarp(to:parameters:)``.
    ///
    /// - Returns: This track with every velocity taken from `performance`.
    ///
    /// - Complexity: The complexity of ``timeWarp(to:parameters:)`` when `warp` is `nil`, and O(*n* log *k* + *c* log *c* + *u* · (*h* log *m* + *w*)) for the transfer, where *n* is the number of notes of this track, *k* the number of knots, *c* the number of candidate pairs (a few for each note), *u* the number of notes without a partner, *h* the number of keys in reach, *m* the number of notes of `performance`, and *w* the number of its notes in reach of one note.
    public func applyingVelocities(from performance: IndexedTrack, warp: TimeWarp? = nil) -> IndexedTrack {
        guard !self.notes.isEmpty, !performance.notes.isEmpty else { return self }
        let warp = warp ?? self.timeWarp(to: performance)
        
        var notes = self.notes
        let onsets = [Double](unsafeUninitializedCapacity: notes.count) { buffer, initializedCount in
            notes.withUnsafeBufferPointer { notes in
                var index = 0
                while index < notes.count {
                    buffer[index] = warp.map(notes[index].onset)
                    index &+= 1
                }
            }
            initializedCount = notes.count
        }
        
        let lanes = self.lanes
        let partners = VelocityTransfer.partners(onsets: onsets, sheet: lanes, performance: performance.lanes, window: VelocityTransfer.matchWindow)
        
        var fill: VelocityTransfer.Fill?
        performance.notes.withUnsafeBufferPointer { performanceNotes in
            notes.withUnsafeMutableBufferPointer { notes in
                var index = 0
                while index < notes.count {
                    let partner = partners[index]
                    if partner >= 0 {
                        notes[index].velocity = performanceNotes[partner].velocity
                    } else {
                        if fill == nil { fill = VelocityTransfer.Fill(performance: performance) }
                        notes[index].velocity = fill!.velocity(time: onsets[index], pitch: notes[index].pitch)
                    }
                    index &+= 1
                }
            }
        }
        
        // Only velocities changed, so the order, keys and times are those `lanes` was built for.
        return IndexedTrack(validated: notes, sustains: self.sustains, channelEvents: self.channelEvents, metaEvents: self.metaEvents, rawData: self.rawData, profile: self.profile, reusingLayoutOf: lanes)
    }
    
}
