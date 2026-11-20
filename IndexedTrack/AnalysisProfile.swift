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


/// The profile that assumes nothing about where the notes came from.
public struct GenericProfile: AnalysisProfile {
    
    /// Creates the generic profile.
    public init() {
        
    }
    
}


extension AnalysisProfile where Self == GenericProfile {
    
    /// The profile that assumes nothing about where the notes came from.
    public static var generic: GenericProfile {
        GenericProfile()
    }
    
}
