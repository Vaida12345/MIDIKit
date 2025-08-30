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
public struct MIDISustainEvents: ArrayRepresentable, DisjointIntervals, Sendable, Equatable, DetailedStringConvertible {
    
    public var contents: [Element]
    
    
    /// - Complexity: O(*n* log *n*), sorting.
    @inlinable
    public mutating func append(contentsOf: MIDISustainEvents) {
        self.contents.append(contentsOf: contentsOf.contents)
        self.contents.sort(by: { $0.onset < $1.onset })
    }
    
    /// - Complexity: O(*n* log *n*), sorting.
    @inlinable
    public mutating func append(_ sustain: MIDISustainEvent) {
        self.contents.append(sustain)
        self.contents.sort(by: { $0.onset < $1.onset })
    }
    
    @inlinable
    public init(_ sustains: [Element] = []) {
        self.contents = sustains.sorted(by: { $0.onset < $1.onset })
    }
    
    
    public typealias Element = MIDISustainEvent
    
    public func detailedDescription(using descriptor: DetailedDescription.Descriptor<MIDISustainEvents>) -> any DescriptionBlockProtocol {
        descriptor.sequence("", of: self)
    }
    
}
