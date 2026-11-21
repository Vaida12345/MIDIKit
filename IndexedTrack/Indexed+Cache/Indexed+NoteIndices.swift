//
//  Indexed+NoteIndices.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-21.
//

import MIDIKit


extension IndexedTrack {

    /// The indices in ``IndexedTrack/notes`` of the notes of a ``Lane`` or a ``Chord``, in the same order as its notes.
    ///
    /// A lane or a chord is reached with two kinds of number: a *position*, where a note is within the lane or chord, and a *note index*, where it is in ``IndexedTrack/notes``. Positions are always the subscripts, starting at 0, of a lane, a chord, ``Chords`` and this collection; note indices are only ever the elements of this collection. So for every position `p` of a lane:
    ///
    /// ```swift
    /// track.notes[lane.noteIndices[p]] == lane[p]
    /// ```
    ///
    /// Use the note indices to edit the notes in ``modifyingNotes(_:)``.
    public struct NoteIndices: RandomAccessCollection, Sendable {

        /// The indices in `notes`, as a slice of the members of ``Lanes`` or ``Chords``, whose first element is at `members.startIndex`, not `0`.
        @usableFromInline
        let members: ArraySlice<Int>

        @inlinable
        init(members: ArraySlice<Int>) {
            self.members = members
        }

        @inlinable public var startIndex: Int { 0 }
        @inlinable public var endIndex: Int { self.members.count }
        @inlinable public var count: Int { self.members.count }
        @inlinable public var isEmpty: Bool { self.members.isEmpty }

        /// Returns the index in ``IndexedTrack/notes`` of the note at the given position.
        ///
        /// - Parameter position: A position in `0..<count`.
        @inlinable public subscript(position: Int) -> Int { self.members[self.members.startIndex &+ position] }

        @inlinable public func makeIterator() -> IndexingIterator<ArraySlice<Int>> { self.members.makeIterator() }

    }

}
