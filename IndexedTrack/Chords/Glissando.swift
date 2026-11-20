//
//  Glissando.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


extension IndexedTrack {

    /// The runs of notes that are a glissando: 11 or more consecutive notes that all move in one direction, each shorter than 0.2 beat and at most 0.2 beat after the one before.
    ///
    /// A run only counts when the first note starts and ends within the same sustain state. Every run is returned once; a note that follows a run directly is not tried as the start of the next.
    ///
    /// - Parameters:
    ///   - notes: Notes sorted by onset.
    ///   - sustains: The sustains of the track.
    ///
    /// - Complexity: O(*n* log *m*), where *n* is the number of notes and *m* the number of sustains.
    static func glissandoRuns(in notes: [MIDINote], sustains: Sustains) -> [Range<Int>] {
        var runs: [Range<Int>] = []

        for isDescending in [true, false] {
            var index = 0
            while index < notes.count {
                defer { index &+= 1 }
                let first = notes[index]
                guard sustains.index(at: first.onset) == sustains.index(at: first.offset) else { continue } // within the same sustain state
                guard index &+ 1 < notes.count else { break }

                var previous = first
                var next = index &+ 1
                while next < notes.count {
                    let candidate = notes[next]
                    guard candidate.offset < candidate.onset + 0.2,
                          isDescending ? candidate.pitch <= previous.pitch : candidate.pitch >= previous.pitch,
                          candidate.onset - previous.onset <= 0.2
                    else { break }
                    previous = candidate
                    next &+= 1
                }
                guard next &- index > 10 else { continue }

                runs.append(index ..< next)
                index = next
            }
        }

        return runs
    }
    
}
