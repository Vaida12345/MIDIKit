//
//  GenericProfile.swift
//  MIDIKit
//
//  Created by Vaida on 2026-11-20.
//


/// The profile that assumes nothing about where the notes came from.
public struct GenericProfile: AnalysisProfile {
    
    /// Creates the generic profile.
    public init() {

    }

    /// Groups the notes of `track` into chords with ``ChordArbiter/generic``.
    public func formChords(in track: IndexedTrack) -> IndexedTrack.Chords {
        ChordArbiter.generic.formChords(in: track)
    }

}


extension AnalysisProfile where Self == GenericProfile {
    
    /// The profile that assumes nothing about where the notes came from.
    public static var generic: GenericProfile {
        GenericProfile()
    }
    
}
