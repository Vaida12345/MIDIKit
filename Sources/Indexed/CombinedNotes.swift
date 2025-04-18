//
//  CombinedNotes.swift
//  PianoVisualizer
//
//  Created by Vaida on 11/25/24.
//

import AudioToolbox


public struct CombinedNotes: OverlappingIntervals {
    
    public var contents: [ReferenceNote]
    
    public init(_ contents: [ReferenceNote]) {
        self.contents = contents
    }
    
    public typealias Element = ReferenceNote
    
}
