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
    /// The chords must be appended in the order of their first notes, and together they must hold every note of the track exactly once. Each chord must be non-empty, its note indices ascending, and hold each key at most once. These are checked with an `assert` in ``build()``.
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
        /// - Complexity: O(1) in release builds, O(*n*) in debug builds, which check the invariants.
        public consuming func build() -> IndexedTrack.Chords {
            let chords = IndexedTrack.Chords(members: self.members, starts: self.starts, features: self.features, notes: self.notes)
            assert(chords.isValid(), "The chords must be non-empty, ascending, ordered by their first notes, hold each key at most once, and hold every note exactly once.")
            return chords
        }

    }

    /// Returns whether the chords meet their invariants.
    ///
    /// For debug-only `assert`s.
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

            var keys = Set<UInt8>()
            var position = lower
            while position < upper {
                let member = self.members[position]
                guard member >= 0 && member < self.notes.count, !seen[member] else { return false }
                seen[member] = true
                guard keys.insert(self.notes[member].pitch).inserted else { return false } // a key twice
                guard position == lower || self.members[position &- 1] < member else { return false } // ascending
                position &+= 1
            }
            chord &+= 1
        }
        return true
    }

}
