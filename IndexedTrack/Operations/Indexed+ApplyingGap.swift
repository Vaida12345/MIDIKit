//
//  IndexedTrack+ApplyingGap.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


extension IndexedTrack {

    /// Returns a track where each note ends `ideal` beats before the next note on its key, as far as that leaves the note long enough.
    ///
    /// For each note followed by another note on the same key:
    ///
    /// - If the gap between them is already at least `ideal`, the note is unchanged.
    /// - Otherwise, the note ends `ideal` before the next one starts, but never shortened to less than `minimumNoteLength`.
    /// - If the next note starts within `minimumNoteLength` of this one, the note is unchanged.
    ///
    /// Notes are never lengthened, and the last note on each key is unchanged. Sustains, control events, meta events and the ``profile`` are kept as they are. Applying the same gap again changes nothing.
    ///
    /// - Parameters:
    ///   - ideal: The ideal gap between consecutive notes on the same key, in beats at 120 BPM. It must be finite and not negative. The default value is `1/8`, a 32nd note.
    ///   - minimumNoteLength: The minimum length a note is shortened to, in beats at 120 BPM. It must be finite and greater than zero. The default value is `1/128`.
    ///
    /// - Complexity: O(*n*), where *n* is the number of notes.
    public func applyingGap(ideal: Double = 1/8, minimumNoteLength: Double = 1/128) -> IndexedTrack {
        precondition(ideal.isFinite && ideal >= 0, "ideal must be finite and not negative")
        precondition(minimumNoteLength.isFinite && minimumNoteLength > 0, "minimumNoteLength must be finite and greater than zero")

        let lanes = self.lanes
        var notes = self.notes // copy

        notes.withUnsafeMutableBufferPointer { notes in
            lanes.members.withUnsafeBufferPointer { members in
                var key = 0
                while key < 88 {
                    var position = lanes.starts[key]
                    let end = lanes.starts[key &+ 1]
                    while position &+ 1 < end {
                        let current = members[position]
                        let next = members[position &+ 1]
                        // Shorten to `ideal` before the next onset, but not below `minimumNoteLength`, and never lengthen.
                        notes[current].offset = Swift.min(notes[current].offset, Swift.max(notes[next].onset - ideal, notes[current].onset + minimumNoteLength))
                        position &+= 1
                    }
                    key &+= 1
                }
            }
        }

        return IndexedTrack(validated: notes, sustains: self.sustains, controlEvents: self.controlEvents, metaEvents: self.metaEvents, profile: self.profile, reusingLayoutOf: lanes)
    }

}
