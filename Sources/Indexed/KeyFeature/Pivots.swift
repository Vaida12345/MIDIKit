//
//  Pivots.swift
//  MIDIKit
//
//  Created by Vaida on 12/24/24.
//


extension KeyFeatures {
    
    public struct Pivots {
        
        public var contents: [Pivot]
        
        public func append(to track: inout MIDITrack) {
            for content in contents {
                track.notes.append(MIDINotes.Note(onset: content.onset, offset: content.onset + content.duration, note: 59, velocity: 127))
            }
            track.notes.contents.sort { $0.onset < $1.onset }
        }
        
        
        public init(_ contents: [Pivot]) {
            self.contents = contents
        }
        
        
        public typealias Element = Pivot
        
    }
    
}


extension KeyFeatures.Pivots: ExpressibleByArrayLiteral, RandomAccessCollection, MutableCollection, BidirectionalCollection {
    
    @inlinable public var startIndex: Int { 0 }
    @inlinable public var endIndex: Int { self.contents.count }
    @inlinable public var count: Int { self.contents.count }
    
    @inlinable
    public subscript(position: Index) -> Element {
        get {
            self.contents[position]
        }
        set {
            self.contents[position] = newValue
        }
    }
    
    @inlinable
    public init(arrayLiteral elements: Element...) {
        self.init(elements)
    }
    
}
