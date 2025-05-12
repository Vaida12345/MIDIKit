//
//  DisjointNotes.swift
//  PianoVisualizer
//
//  Created by Vaida on 11/25/24.
//

import AudioToolbox


public struct DisjointNotes: ArrayRepresentable, DisjointIntervals {
    
    public var contents: [ReferenceNote]
    
    @inlinable
    public init(_ contents: [ReferenceNote]) {
        self.contents = contents
    }
    
    public typealias Element = ReferenceNote
    
}
