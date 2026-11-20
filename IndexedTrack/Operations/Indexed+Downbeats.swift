//
//  Indexed+Downbeats.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


extension IndexedTrack {

    /// Returns the downbeats: the times, in beats at 120 BPM, where the bars start.
    ///
    /// The ``profile`` finds them, through ``AnalysisProfile/downbeats(in:prior:)``. The generic one uses ``DownbeatTracker/generic``, which follows the tempo and the position in the bar together, reading the onsets, the bass, the harmony, the pedal and how long the notes ring; see ``DownbeatTracker``. A profile for a transcriber uses the constants tuned for it, such as ``DownbeatTracker/transkun`` or ``DownbeatTracker/pianoTranscription``.
    ///
    /// Bars of two, three and four beats are found, and the number of beats may change within the piece. A pickup before the first bar is allowed.
    ///
    /// - Parameter prior: Times, in beats, that are known to be downbeats. Each finite, non-negative one is in the result at its exact time, and the bars around it are found to fit it.
    ///
    /// - Returns: Strictly increasing times, in beats. Only `prior` when the track has no notes.
    ///
    /// - Complexity: O(*f* · *s*), where *f* is the number of frames (25 per beat) and *s* the number of states of the tracker (about 9,300), in addition to forming the ``chords`` on first use, for the generic profile.
    ///
    /// ## User-facing Description:
    ///
    /// - Finds where each bar starts, following the tempo as it changes.
    public func downbeats(prior: [Double] = []) -> [Double] {
        self.profile.downbeats(in: self, prior: prior)
    }

}
