//
//  Indexed+PreserveSettings.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import Foundation


extension IndexedTrack {

    /// What ``normalizing(preserve:)`` favors where the sustains do not decide a note's length.
    ///
    /// The raw values match those of `IndexedContainer.PreserveSettings` from MIDIKit 1.x, so values stored by raw value decode to the same case.
    public enum PreserveSettings: String, Hashable, Identifiable, CaseIterable, Sendable, BitwiseCopyable {
        /// Keeps note lengths that let the sustains sound as played, for the most realistic playback.
        case acousticResult = "Acoustic Result"
        /// Ends notes no later than the next chord where possible, so chords overlap less and read more clearly.
        case notesDisplay = "Notes Display"

        public var id: String {
            self.rawValue
        }
    }

}
