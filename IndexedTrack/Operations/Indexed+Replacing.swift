//
//  Indexed+Replacing.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-21.
//

import MIDIKit


extension IndexedTrack {

    /// Returns this track as a container, with the given notes and sustains in place of its own.
    ///
    /// The container is the one ``makeContainer()`` returns: a single track at a constant 120 BPM, with this track's channel events, meta events and raw data, and its time signatures in the tempo track. The notes and sustains are kept exactly as given, without any cleanup.
    ///
    /// Use it to change the notes or sustains of a track without losing its other events, then index the result to analyze it again:
    ///
    /// ```swift
    /// let edited = track.replacing(notes: newNotes).indexed(profile: track.profile)
    /// ```
    ///
    /// - Parameters:
    ///   - notes: The new notes, in beats at 120 BPM, in any order, or `nil` to keep this track's.
    ///   - sustains: The new sustains, in beats at 120 BPM, or `nil` to keep this track's.
    ///
    /// - Complexity: O(*n*), where *n* is the number of events.
    public func replacing(notes: [MIDINote]? = nil, sustains: Sustains? = nil) -> MIDIContainer {
        var container = self.makeContainer()
        // `makeContainer()` builds a single track at 120 BPM, so the new times need no conversion.
        if let notes { container.tracks[0].notes = MIDINotes(notes) }
        if let sustains { container.tracks[0].sustains = sustains }
        return container
    }

}
