//
//  AnalysisProfile.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


/// The choices the analyses of an ``IndexedTrack`` make, such as how chords are formed.
///
/// Each requirement is a hook that one analysis calls, so that the analyses can follow what is known about where the notes came from, for example the transcriber that produced them, without depending on it.
public protocol AnalysisProfile: Sendable {

    /// Groups the notes of `track` into chords: keys that are pressed together.
    ///
    /// ``IndexedTrack/chords`` calls this the first time it is accessed and caches the result, so the implementation must be deterministic: the same track always gives the same chords. It must not read `track.chords`, which would never return; reading ``IndexedTrack/lanes`` and ``IndexedTrack/intervalTree`` is fine.
    ///
    /// Use ``IndexedTrack/Chords/Builder`` to create the return value, or ``ChordArbiter/formChords(in:)`` with the constants that suit the notes.
    ///
    /// - Parameter track: The track whose notes are grouped.
    func formChords(in track: IndexedTrack) -> IndexedTrack.Chords

}
