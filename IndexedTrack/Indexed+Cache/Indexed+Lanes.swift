//
//  Indexed+Lanes.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit
import Intervals


extension IndexedTrack {
    
    /// The notes grouped by key.
    ///
    /// The lanes are computed the first time they are accessed, in O(*n*), and then shared by every copy of this track.
    ///
    /// - Tip: Keep the return value cached instead of accessing it repeatedly.
    public var lanes: Lanes {
        if let existing = self.cache.lanes.withLock({ $0 }) {
            return existing
        }
        
        // build the lanes, a stable counting sort by key.
        // `notes` is sorted by onset, hence notes within a lane are also sorted by onset.
        let notes = self.notes
        
        // starts[k + 1] counts the notes of key k, then prefix sums make it the end of lane k.
        var starts = [Int](repeating: 0, count: 89)
        for note in notes {
            assert(note.pitch >= 21 && note.pitch <= 108, "pitch \(note.pitch) is out of 21...108")
            starts[Int(note.pitch) &- 20] &+= 1
        }
        var k = 1
        while k < starts.count {
            starts[k] &+= starts[k &- 1]
            k &+= 1
        }
        
        var cursors = starts
        let members = [Int](unsafeUninitializedCapacity: notes.count) { buffer, initializedCount in
            var i = 0
            while i < notes.count {
                let lane = Int(notes[i].pitch) &- 21
                buffer[cursors[lane]] = i
                cursors[lane] &+= 1
                i &+= 1
            }
            initializedCount = notes.count
        }
        
        let lanes = Lanes(members: members, starts: starts, notes: self.notes)
        
        // Another caller may have stored its lanes in the meantime; keep the first, they are identical.
        return self.cache.lanes.withLock { stored in
            if let stored { return stored }
            stored = lanes
            return lanes
        }
    }
    
    
    /// The notes of an ``IndexedTrack``, grouped by key.
    ///
    /// A collection of the 88 lanes, indexed by key, `21...108`: `for lane in track.lanes` visits every key from the lowest, and ``subscript(_:)`` gets the notes of a single key.
    public struct Lanes: RandomAccessCollection, Sendable {
        /// note indices grouped by key, by onset within each key
        let members: [Int]
        /// key k is `members[starts[k]..<starts[k + 1]]`
        let starts: [Int]
        
        /// The CoW copy of `IndexedTrack`'s notes.
        let notes: [MIDINote]
        
        /// The lowest key, 21.
        public var startIndex: UInt8 { 21 }
        /// One past the highest key, 108.
        public var endIndex: UInt8 { 109 }
        
        /// Returns the lane of the given key.
        ///
        /// - Parameter laneIndex: The key, `21...108`.
        public subscript(_ laneIndex: UInt8) -> Lane {
            precondition(laneIndex >= 21 && laneIndex <= 108)
            
            let index = Int(laneIndex) &- 21
            let lowerBound = self.starts[index]
            let upperBound = self.starts[index + 1]
            return Lane(members: self.members[lowerBound..<upperBound], notes: self.notes)
        }
    }
    
    /// The notes of a single key, sorted by onset.
    ///
    /// The notes of a lane never overlap, as the notes of an ``IndexedTrack`` on the same key are disjoint. A lane shares storage with its track, so creating one is cheap, and it stays valid after the track is gone.
    public struct Lane: RandomAccessCollection, Sendable, Intervals::DisjointIntervals {
        
        /// The indices in `notes` of the notes in this lane, sorted by onset.
        ///
        /// As a slice of ``Lanes``'s members, it keeps their indices: the first member is at `members.startIndex`, not `0`.
        @usableFromInline
        let members: ArraySlice<Int>
        
        /// The CoW copy of `IndexedTrack`'s notes.
        @usableFromInline
        let notes: [MIDINote]
        
        @inlinable public var count: Int { self.members.count }
        @inlinable public var isEmpty: Bool { self.members.isEmpty }
        
        @inlinable public var startIndex: Int { 0 }
        @inlinable public var endIndex: Int { self.members.count }
        
        /// The indices in ``IndexedTrack/notes`` of the notes of this lane, in the same order: `notes[noteIndices[p]]` is `self[p]` for every position `p`.
        @inlinable public var noteIndices: NoteIndices { NoteIndices(members: self.members) }
        
        /// Returns the note at the given position in this lane.
        ///
        /// - Parameter index: A position in this lane, in `0..<count`. It is not an index in ``IndexedTrack/notes``; ``noteIndices`` gives those.
        @inlinable public subscript(index: Int) -> MIDINote { return self.notes[self.noteIndices[index]] }
    }
    
}
