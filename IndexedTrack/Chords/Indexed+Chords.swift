//
//  Indexed+Chords.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


extension IndexedTrack {

    /// The notes grouped into chords: keys that are pressed together.
    ///
    /// The chords are formed by the ``profile``'s ``AnalysisProfile/formChords(in:)`` the first time they are accessed, and then shared by every copy of this track.
    ///
    /// - Tip: Keep the return value cached instead of accessing it repeatedly.
    public var chords: Chords {
        if let existing = self.cache.chords.withLock({ $0 }) {
            return existing
        }

        let chords = self.profile.formChords(in: self)

        // Another caller may have stored its chords in the meantime; keep the first, they are identical as the profile is deterministic.
        return self.cache.chords.withLock { stored in
            if let stored { return stored }
            stored = chords
            return chords
        }
    }


    /// The notes of an ``IndexedTrack``, grouped into chords.
    ///
    /// Every note is in exactly one chord. The chords are sorted by their first note, hence by ``Chord/leadingOnset``.
    ///
    /// Use ``Builder`` to create chords.
    public struct Chords: RandomAccessCollection, Sendable {

        /// note indices grouped by chord, ascending within each chord
        let members: [Int]
        /// chord c is `members[starts[c]..<starts[c + 1]]`
        let starts: [Int]
        /// the features of each chord
        let features: [Chord.Features]

        /// The CoW copy of `IndexedTrack`'s notes.
        let notes: [MIDINote]

        @inlinable public var startIndex: Int { 0 }
        public var endIndex: Int { self.starts.count &- 1 }

        /// Returns the chord at the given position.
        ///
        /// - Parameter index: A position in `0..<count`.
        public subscript(index: Int) -> Chord {
            Chord(members: self.members[self.starts[index]..<self.starts[index &+ 1]], notes: self.notes, features: self.features[index])
        }
    }

    /// Keys that are pressed together, sorted by (onset, pitch).
    ///
    /// A chord is never empty and holds each key at most once. It shares storage with its track, so creating one is cheap, and it stays valid after the track is gone.
    public struct Chord: RandomAccessCollection, Sendable {

        /// The indices in `notes` of the notes in this chord, ascending.
        ///
        /// As a slice of ``Chords``'s members, it keeps their indices: the first member is at `members.startIndex`, not `0`.
        @usableFromInline
        let members: ArraySlice<Int>

        /// The CoW copy of `IndexedTrack`'s notes.
        @usableFromInline
        let notes: [MIDINote]

        /// What the chord-forming algorithm found about this chord.
        public let features: Features

        @inlinable public var count: Int { self.members.count }
        @inlinable public var isEmpty: Bool { self.members.isEmpty }

        @inlinable public var startIndex: Int { 0 }
        @inlinable public var endIndex: Int { self.members.count }

        /// Returns the index in ``IndexedTrack/notes`` of the note at the given position in this chord.
        ///
        /// - Parameter index: A position in this chord, in `0..<count`.
        @inlinable package func noteIndex(at index: Int) -> Int { members[members.startIndex &+ index] }

        /// Returns the note at the given position in this chord.
        ///
        /// - Parameter index: A position in this chord, in `0..<count`.
        @inlinable public subscript(index: Int) -> MIDINote { self.notes[self.noteIndex(at: index)] }

        /// The onset of the earliest note.
        ///
        /// - Complexity: O(1)
        public var leadingOnset: Double {
            self.notes[self.members.first!].onset
        }

        /// The latest offset of any note.
        ///
        /// - Complexity: O(*k*), where *k* is the number of notes in the chord.
        public var maxOffset: Double {
            var result = -Double.infinity
            for member in self.members {
                result = Swift.max(result, self.notes[member].offset)
            }
            return result
        }

        /// The time from the earliest onset to the latest offset.
        ///
        /// - Complexity: O(*k*), where *k* is the number of notes in the chord.
        public var duration: Double {
            self.maxOffset - self.leadingOnset
        }

        /// The lowest and highest keys of the chord.
        ///
        /// - Complexity: O(*k*), where *k* is the number of notes in the chord.
        public var pitchRange: ClosedRange<UInt8> {
            var lowest = UInt8.max
            var highest = UInt8.min
            for member in self.members {
                let pitch = self.notes[member].pitch
                lowest = Swift.min(lowest, pitch)
                highest = Swift.max(highest, pitch)
            }
            return lowest...highest
        }


        /// What the chord-forming algorithm found about a chord.
        public struct Features: OptionSet, Sendable, Hashable {

            public let rawValue: UInt8

            public init(rawValue: UInt8) {
                self.rawValue = rawValue
            }

            /// The chord is a single note of a glissando, which is never merged with other notes.
            public static let glissando = Features(rawValue: 1 << 0)

        }
    }

}
