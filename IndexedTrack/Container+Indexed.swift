//
//  Container+Indexed.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-21.
//

import MIDIKit


extension MIDIContainer {

    /// Returns every track of the container merged into one, cleaned up and indexed for analysis.
    ///
    /// This is the same as ``IndexedTrack/init(_:profile:minimumConsecutiveNotesGap:)``, which describes the cleanup.
    ///
    /// - Parameters:
    ///   - profile: The choices the analyses of the track make.
    ///   - minimumConsecutiveNotesGap: The minimum gap between consecutive notes on the same key, in beats at 120 BPM. It must be finite and greater than zero. The default value is `1/128`.
    ///
    /// - Complexity: O(*n* log *n*), where *n* is the number of notes.
    public func indexed(profile: some AnalysisProfile = .generic, minimumConsecutiveNotesGap: Double = 1/128) -> IndexedTrack {
        IndexedTrack(self, profile: profile, minimumConsecutiveNotesGap: minimumConsecutiveNotesGap)
    }

}
