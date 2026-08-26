//
//  Controls.swift
//  MIDIKit
//
//  Created by Vaida on 2026-07-04.
//

import OSLog
import AudioToolbox
import DetailedDescription


/// To support efficient lookup, the sustain events are sorted on initialization.
///
/// The contents are not guaranteed to be sorted after iteration, as `container` does not update `contents` when the `onset`s for individual notes change.
public struct MIDIControlEvents: Sendable, Equatable, DetailedStringConvertible {
    
    public var contents: [Element]
    
    /// - Complexity: O(*n* log *n*), sorting.
    @inlinable
    public init(_ contents: [Element] = []) {
        self.contents = contents.sorted(by: { $0.onset < $1.onset })
    }
    
    
    public typealias Element = MIDIControlEvent
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDIControlEvents>) -> any DescriptionBlockProtocol {
        descriptor.sequence("", of: self)
    }
}


extension MIDIControlEvents: ExpressibleByArrayLiteral, RandomAccessCollection, MutableCollection, BidirectionalCollection {
    
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
