//
//  Sustains.swift
//  MIDIKit
//
//  Created by Vaida on 9/3/24.
//

import OSLog
import AudioToolbox
import DetailedDescription


/// To support efficient lookup, the sustain events are sorted on initialization.
///
/// The contents are not guaranteed to be sorted after iteration, as `container` does not update `contents` when the `onset`s for individual notes change.
public struct MIDISustainEvents: DisjointIntervals, Sendable, Equatable, DetailedStringConvertible {
    
    public var contents: [Element]
    
    
    /// - Complexity: O(*n* log *n*), sorting.
    @inlinable
    public mutating func insert(contentsOf: MIDISustainEvents) {
        self.contents.append(contentsOf: contentsOf.contents)
        self.contents.sort(by: { $0.onset < $1.onset })
    }
    
    /// - Complexity: O(*n*), shifting.
    @inlinable
    public mutating func insert(_ sustain: MIDISustainEvent) {
        let index = self.firstIndex(after: sustain.onset) ?? self.contents.endIndex
        self.contents.insert(sustain, at: index)
    }
    
    /// - Complexity: O(*n* log *n*), sorting.
    @inlinable
    public init(_ sustains: [Element] = []) {
        self.contents = sustains.sorted(by: { $0.onset < $1.onset })
    }
    
    
    public typealias Element = MIDISustainEvent
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDISustainEvents>) -> any DescriptionBlockProtocol {
        descriptor.sequence("", of: self)
    }
    
}


extension MIDISustainEvents: ExpressibleByArrayLiteral, RandomAccessCollection, MutableCollection, BidirectionalCollection {
    
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


extension MIDISustainEvents {
    
    @inlinable
    mutating func mutatingForEach(body: (_ index: Index, _ element: inout Element) -> Void) {
        var i = 0
        while i < self.endIndex {
            body(i, &self[i])
            
            i &+= 1
        }
    }
    
}
