//
//  IndexedTrack.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//

import MIDIKit


/// A piano performance merged into a single track, cleaned up and indexed for analysis.
///
/// An indexed track never changes after it is created. Operations that transform it return a new indexed track with the same ``profile``, and ``Lanes`` and other derived structures are computed on first use, then shared by every copy.
public struct IndexedTrack: Sendable {
    
    /// Cleaned-up notes sorted by (onset, pitch): pitches 21...108, same-key notes disjoint and gapped.
    public let notes: [MIDINote]
    /// The sustains of every source track, merged: sorted and disjoint.
    public let sustains: Sustains
    /// The channel events of every source track, sorted by onset.
    public let channelEvents: [MIDIChannelEvent]
    /// The meta events of every source track.
    public let metaEvents: [MIDIMetaEvent]
    
    /// The raw messages, such as system exclusive (SysEx) messages, of every track, sorted by timestamp.
    public let rawData: [MIDIRawData]
    
    /// The choices the analyses of this track make, such as how chords are formed.
    public let profile: any AnalysisProfile
    
    /// The structures derived from the notes, computed on first use and shared by every copy of this track.
    internal let cache = Cache()
    
}
