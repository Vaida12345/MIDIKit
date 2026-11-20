//
//  AnalysisProfile.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


/// The choices the analyses of an ``IndexedTrack`` make, such as how chords are formed and how downbeats are found.
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

    /// Returns `track` without the notes that are artifacts of how it was produced, such as stray quiet notes from a transcriber.
    ///
    /// ``IndexedTrack/removingArtifacts(threshold:proximityThreshold:)`` calls this. The implementation must be deterministic, and must return a track that keeps the ``IndexedTrack/profile``, sustains, channel events and meta events of `track`, and whose notes still meet the invariants of ``IndexedTrack``. Removing notes and extending the note before a removed one up to where that one ended keeps them.
    ///
    /// The default implementation uses ``GenericProfile/removingArtifacts(from:threshold:proximityThreshold:)``.
    ///
    /// - Parameters:
    ///   - track: The track to clean up.
    ///   - threshold: The velocity at or under which a note may be an artifact. A profile that knows better may ignore it.
    ///   - proximityThreshold: How close, in beats, an artifact is to the note before it. A profile that knows better may ignore it.
    func removingArtifacts(from track: IndexedTrack, threshold: UInt8, proximityThreshold: Double) -> IndexedTrack

    /// Finds the downbeats of `track`: the times, in beats, where its bars start.
    ///
    /// ``IndexedTrack/downbeats(prior:)`` calls this. The implementation must be deterministic, must return strictly increasing times that include every finite, non-negative time in `prior`, and must not read note offsets that the transcriber does not report faithfully.
    ///
    /// Use ``DownbeatTracker/downbeats(in:prior:)`` with the constants that suit the notes, such as ``DownbeatTracker/transkun`` or ``DownbeatTracker/pianoTranscription``. The default implementation uses ``DownbeatTracker/generic``.
    ///
    /// - Parameters:
    ///   - track: The track whose downbeats are found.
    ///   - prior: Times, in beats, that are known to be downbeats.
    func downbeats(in track: IndexedTrack, prior: [Double]) -> [Double]

}


extension AnalysisProfile {

    /// Returns `track` without the stray quiet notes, using ``GenericProfile/removingArtifacts(from:threshold:proximityThreshold:)``.
    public func removingArtifacts(from track: IndexedTrack, threshold: UInt8, proximityThreshold: Double) -> IndexedTrack {
        GenericProfile().removingArtifacts(from: track, threshold: threshold, proximityThreshold: proximityThreshold)
    }

    /// Finds the downbeats of `track` with ``DownbeatTracker/generic``.
    public func downbeats(in track: IndexedTrack, prior: [Double]) -> [Double] {
        DownbeatTracker.generic.downbeats(in: track, prior: prior)
    }

}
