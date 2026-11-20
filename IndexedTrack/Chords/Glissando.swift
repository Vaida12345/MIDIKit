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
    ///   - sustains: Sorted, disjoint sustains.
    ///
    /// - Complexity: O(*n* log *m*), where *n* is the number of notes and *m* the number of sustains.
    static func glissandoRuns(in notes: [MIDINote], sustains: [MIDISustainEvent]) -> [Range<Int>] {
        var runs: [Range<Int>] = []

        for isDescending in [true, false] {
            var index = 0
            while index < notes.count {
                defer { index &+= 1 }
                let first = notes[index]
                guard sustainIndex(at: first.onset, in: sustains) == sustainIndex(at: first.offset, in: sustains) else { continue } // within the sustain
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

    /// Returns the index of the sustain that contains `t`, bounds inclusive, or `nil` when no sustain does.
    ///
    /// - Complexity: O(log *m*), where *m* is the number of sustains.
    private static func sustainIndex(at t: Double, in sustains: [MIDISustainEvent]) -> Int? {
        // the number of sustains whose onset is at most `t`
        var low = 0
        var high = sustains.count
        while low < high {
            let middle = Int(UInt(bitPattern: low &+ high) >> 1)
            if sustains[middle].onset <= t {
                low = middle &+ 1
            } else {
                high = middle
            }
        }
        guard low > 0, sustains[low &- 1].offset >= t else { return nil }
        return low &- 1
    }

}
