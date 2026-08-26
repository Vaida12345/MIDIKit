//
//  Notes.swift
//  MIDIKit
//
//  Created by Vaida on 8/26/24.
//

import Essentials
import FinderItem
import ConcurrentStream
import OSLog
import DetailedDescription
import Accelerate
import NativeImage


/// MIDI Notes are **not** sorted.
///
/// Although `MIDIKit` does not require the notes to be sorted, SMF spec does. Hence on read, all the notes are sorted.
public struct MIDINotes:  Sendable, Equatable, DetailedStringConvertible {
    
    public var contents: [MIDITrack.Note]
    
    @inlinable
    public mutating func append(contentsOf: MIDINotes) {
        self.contents.append(contentsOf: contentsOf.contents)
    }
    
    @inlinable
    public mutating func append(_ note: Note) {
        self.contents.append(note)
    }
    
    /// The range of note value.
    ///
    /// - Complexity: O(*n*)
    public func noteRange() -> (min: UInt8, max: UInt8)? {
        guard !self.isEmpty else { return nil }
        let notes = self.contents.map(\.note)
        
        return (notes.min()!, notes.max()!)
    }
    
    /// Sort the contents.
    public mutating func sort() {
        self.contents.sort()
    }
    
    public typealias Note = MIDITrack.Note
    
    public typealias Element = Note
    
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDINotes>) -> any DescriptionBlockProtocol {
        descriptor.sequence(for: \.contents)
    }
    
    public static let preview: MIDINotes = MIDINotes((21...108).map { MIDINote(onset: Double($0) - 21, offset: Double($0) - 20, note: $0, velocity: $0, channel: 0) })
    
    
    @inlinable
    public init(_ contents: consuming [MIDITrack.Note]) {
        self.contents = contents
    }
    
}


extension MIDINotes: ExpressibleByArrayLiteral, RandomAccessCollection {
    
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
    public init(arrayLiteral elements: MIDINote...) {
        self.init(elements)
    }
    
}



extension MIDINotes {
    
    @inlinable
    mutating func mutatingForEach(body: (_ index: Index, _ element: inout Element) -> Void) {
        var i = 0
        while i < self.endIndex {
            body(i, &self[i])
            
            i &+= 1
        }
    }
    
}
