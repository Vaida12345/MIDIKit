//
//  Indexed+ModifyingNotes.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-21.
//

import MIDIKit


extension IndexedTrack {

    /// Returns a track whose notes were changed by `body`, keeping their order and keys.
    ///
    /// `body` gets a copy of ``notes`` to edit. It may change the offsets, velocities, release velocities and channels; it must not change the number of notes, their onsets or their keys, and each note must still end after it starts and before the next note on its key starts. These rules are checked with an `assert`.
    ///
    /// Use the ``Lane/noteIndices`` of ``lanes`` and the ``Chord/noteIndices`` of ``chords`` to find the notes to change. For example, to end each note an eighth of a beat before the next note on its key:
    ///
    /// ```swift
    /// let lanes = track.lanes
    /// let gapped = track.modifyingNotes { notes in
    ///     for lane in lanes {
    ///         for (current, next) in zip(lane.noteIndices, lane.noteIndices.dropFirst()) {
    ///             notes[current].offset = min(notes[current].offset, max(notes[next].onset - 1/8, notes[current].onset + 1/128))
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Sustains, channel events, meta events, raw data and the ``profile`` are kept. The result reuses the layout of the ``lanes``, and forms its ``chords`` again on first use.
    ///
    /// To move onsets, change keys, or add or remove notes, use ``replacing(notes:sustains:)`` and index the result.
    ///
    /// - Parameter body: A closure that edits the notes.
    ///
    /// - Complexity: O(*n*), where *n* is the number of notes, for the copy, in addition to the work of `body`.
    public func modifyingNotes(_ body: (inout [MIDINote]) throws -> Void) rethrows -> IndexedTrack {
        let lanes = self.lanes
        var notes = self.notes
        try body(&notes)
        assert(notes.count == self.notes.count && zip(notes, self.notes).allSatisfy { $0.onset == $1.onset && $0.pitch == $1.pitch }, "modifyingNotes(_:) must not change the number, onsets or keys of the notes; use replacing(notes:sustains:) for that.")
        return IndexedTrack(validated: notes, sustains: self.sustains, channelEvents: self.channelEvents, metaEvents: self.metaEvents, rawData: self.rawData, profile: self.profile, reusingLayoutOf: lanes)
    }

}
