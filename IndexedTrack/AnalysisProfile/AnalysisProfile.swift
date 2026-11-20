//
//  AnalysisProfile.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


/// The choices the analyses of an ``IndexedTrack`` make, such as how chords are formed.
///
/// It has no requirements yet. Hooks for the analyses will be added as protocol requirements with default implementations, so that a profile overrides only the analyses it cares about.
public protocol AnalysisProfile: Sendable {
    
}
