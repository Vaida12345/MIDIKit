//
//  Indexed+RemovingArtifacts.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


extension IndexedTrack {

    /// Returns a track without the notes that are artifacts of how it was produced, such as the stray quiet notes from PianoTranscription.
    ///
    /// The ``profile`` decides what an artifact is, through ``AnalysisProfile/removingArtifacts(from:threshold:proximityThreshold:)``. The generic one removes runs of quiet notes on a key that closely follow a louder note, and extends that note over them; see ``GenericProfile/removingArtifacts(from:threshold:proximityThreshold:)``.
    ///
    /// Sustains, channel events, meta events and the ``profile`` are kept.
    ///
    /// - Parameters:
    ///   - threshold: The velocity at or under which a note may be an artifact.
    ///   - proximityThreshold: How close, in beats, an artifact is to the note before it. The default value is `1/2`, an eighth note.
    ///
    /// ## User-facing Description:
    ///
    /// - Removes tiny stray notes for a cleaner, less noisy sound.
    public func removingArtifacts(threshold: UInt8, proximityThreshold: Double = 1/2) -> IndexedTrack {
        self.profile.removingArtifacts(from: self, threshold: threshold, proximityThreshold: proximityThreshold)
    }

}
