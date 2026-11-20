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
    
}


extension AnalysisProfile where Self == GenericProfile {
    
    /// The profile that assumes nothing about where the notes came from.
    public static var generic: GenericProfile {
        GenericProfile()
    }
    
}
