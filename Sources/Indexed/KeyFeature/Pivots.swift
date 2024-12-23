//
//  Pivots.swift
//  MIDIKit
//
//  Created by Vaida on 12/24/24.
//


extension KeyFeatures {
    
    public struct Pivots: ArrayRepresentable {
        
        public var contents: [Pivot]
        
        public func append(to track: inout MIDITrack) {
            for content in contents {
                track.notes.append(MIDINotes.Note(onset: content.onset, offset: content.onset + content.duration, note: 59, velocity: 127))
            }
        }
        
        
        public init(_ contents: [Pivot]) {
            self.contents = contents
        }
        
        
        public typealias Element = Pivot
        
    }
    
}
