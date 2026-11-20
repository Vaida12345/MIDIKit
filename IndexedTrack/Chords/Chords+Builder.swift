//
//  Chords+Builder.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


extension IndexedTrack.Chords {

    /// Builds the chords of a track, one chord at a time.
    ///
    /// Use it in ``AnalysisProfile/formChords(in:)`` to return the chords the profile forms:
    ///
    /// ```swift
    /// var builder = IndexedTrack.Chords.Builder(for: track)
    /// builder.append([0, 1, 2])
    /// builder.append([3])
    /// return builder.build()
    /// ```
    ///
    /// The chords must be appended in the order of their first notes, and together they must hold every note of the track exactly once. Each chord must be non-empty, its note indices ascending, and hold each key at most once. ``build()`` checks these, and stops the program if one is broken, as the analyses index the track's notes with the chords, some through unchecked pointers.
    public struct Builder {

        private var members: [Int]
        private var starts: [Int]
        private var features: [IndexedTrack.Chord.Features]
        private let notes: [MIDINote]

        /// Creates a builder for the chords of `track`.
        ///
        /// - Parameter track: The track whose notes the chords hold.
        public init(for track: IndexedTrack) {
            self.notes = track.notes
            self.members = []
            self.members.reserveCapacity(track.notes.count)
            self.starts = [0]
            self.features = []
        }

        /// Appends a chord.
        ///
        /// - Parameters:
        ///   - noteIndices: The indices in ``IndexedTrack/notes`` of the notes of the chord, ascending.
        ///   - features: What was found about the chord.
        public mutating func append(_ noteIndices: some Sequence<Int>, features: IndexedTrack.Chord.Features = []) {
            self.members.append(contentsOf: noteIndices)
            self.starts.append(self.members.count)
            self.features.append(features)
        }

        /// Returns the chords.
        ///
        /// - Complexity: O(*n*), where *n* is the number of notes, to check the invariants.
        public consuming func build() -> IndexedTrack.Chords {
            let chords = IndexedTrack.Chords(members: self.members, starts: self.starts, features: self.features, notes: self.notes)
            precondition(chords.isValid(), "The chords must be non-empty, ascending, ordered by their first notes, hold each key at most once, and hold every note exactly once.")
            return chords
        }

    }

    /// Returns whether the chords meet their invariants.
    func isValid() -> Bool {
        guard self.members.count == self.notes.count else { return false }

        var seen = [Bool](repeating: false, count: self.notes.count)
        var previousFirst = -1
        var chord = 0
        while chord < self.count {
            let lower = self.starts[chord]
            let upper = self.starts[chord &+ 1]
            guard lower < upper else { return false } // empty
            guard self.members[lower] > previousFirst else { return false } // ordered by first note
            previousFirst = self.members[lower]

            // The keys of the chord, one bit for each pitch: the pitches of an indexed track are in `21...108`.
            var keys: (low: UInt64, high: UInt64) = (0, 0)
            var position = lower
            while position < upper {
                let member = self.members[position]
                guard member >= 0 && member < self.notes.count, !seen[member] else { return false }
                seen[member] = true
                let pitch = self.notes[member].pitch
                let bit = UInt64(1) << UInt64(pitch & 63)
                if pitch < 64 {
                    guard keys.low & bit == 0 else { return false } // a key twice
                    keys.low |= bit
                } else {
                    guard keys.high & bit == 0 else { return false } // a key twice
                    keys.high |= bit
                }
                guard position == lower || self.members[position &- 1] < member else { return false } // ascending
                position &+= 1
            }
            chord &+= 1
        }
        return true
    }

}
